# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

class hadoop {

  /**
   * Common definitions for hadoop nodes.
   * They all need these files so we can access hdfs/jobs from any node
   */
   
  class kerberos {
    require kerberos::client

    kerberos::host_keytab { "hdfs":
      princs => [ "host", "hdfs" ],
      spnego => true,
    }
   
    kerberos::host_keytab { [ "yarn", "mapred" ]:
      tag    => "mapreduce",
      spnego => true,
    }
  }

  class common {
    if ($auth == "kerberos") {
      include hadoop::kerberos
    }

    file {
      "/etc/hadoop/conf/hadoop-env.sh":
        content => template('hadoop/hadoop-env.sh'),
        require => [Package["hadoop"]],
    }

    package { "hadoop":
      ensure => latest,
      require => Package["jdk"],
    }

    #FIXME: package { "hadoop-native":
    #  ensure => latest,
    #  require => [Package["hadoop"]],
    #}
  }

  class common-yarn inherits common {
    package { "hadoop-yarn":
      ensure => latest,
      require => [Package["jdk"], Package["hadoop"]],
    }
 
    file {
      "/etc/hadoop/conf/yarn-site.xml":
        content => template('hadoop/yarn-site.xml'),
        require => [Package["hadoop"]],
    }

    file { "/etc/hadoop/conf/container-executor.cfg":
      content => template('hadoop/container-executor.cfg'), 
      require => [Package["hadoop"]],
    }
  }

  class common-hdfs inherits common {
    if ($auth == "kerberos" and $ha == "enabled") {
      fail("High-availability secure clusters are not currently supported")
    }

    if ($ha == 'enabled') {
      $nameservice_id = extlookup("hadoop_ha_nameservice_id", "ha-nn-uri")
    }

    package { "hadoop-hdfs":
      ensure => latest,
      require => [Package["jdk"], Package["hadoop"]],
    }
 
    file {
      "/etc/hadoop/conf/core-site.xml":
        content => template('hadoop/core-site.xml'),
        require => [Package["hadoop"]],
    }

    file {
      "/etc/hadoop/conf/hdfs-site.xml":
        content => template('hadoop/hdfs-site.xml'),
        require => [Package["hadoop"]],
    }
  }

  class common-mapred-app inherits common-hdfs {
    package { "hadoop-mapreduce":
      ensure => latest,
      require => [Package["jdk"], Package["hadoop"]],
    }

    file {
      "/etc/hadoop/conf/mapred-site.xml":
        content => template('hadoop/mapred-site.xml'),
        require => [Package["hadoop"]],
    }

    file { "/etc/hadoop/conf/taskcontroller.cfg":
      content => template('hadoop/taskcontroller.cfg'), 
      require => [Package["hadoop"]],
    }
  }

  define datanode ($namenode_host, $namenode_port, $port = "50075", $auth = "simple", $dirs = ["/tmp/data"], $ha = 'disabled') {

    $hadoop_namenode_host           = $namenode_host
    $hadoop_namenode_port           = $namenode_port
    $hadoop_datanode_port           = $port
    $hadoop_security_authentication = $auth

    if ($ha == 'enabled') {
      # Needed by hdfs-site.xml
      $sshfence_keydir  = "/usr/lib/hadoop/.ssh"
      $sshfence_keypath = "$sshfence_keydir/id_sshfence"
      $sshfence_user    = extlookup("hadoop_ha_sshfence_user",    "hdfs") 
      $shared_edits_dir = extlookup("hadoop_ha_shared_edits_dir", "/hdfs_shared")
    }

    include common-hdfs

    package { "hadoop-hdfs-datanode":
      ensure => latest,
      require => Package["jdk"],
    }

    file {
      "/etc/default/hadoop-hdfs-datanode":
        content => template('hadoop/hadoop-hdfs'),
        require => [Package["hadoop-hdfs-datanode"]],
    }

    service { "hadoop-hdfs-datanode":
      ensure => running,
      hasstatus => true,
      subscribe => [Package["hadoop-hdfs-datanode"], File["/etc/hadoop/conf/core-site.xml"], File["/etc/hadoop/conf/hdfs-site.xml"], File["/etc/hadoop/conf/hadoop-env.sh"]],
      require => [ Package["hadoop-hdfs-datanode"], File[$dirs] ],
    }
    Kerberos::Host_keytab <| title == "hdfs" |> -> Service["hadoop-hdfs-datanode"]

    file { $dirs:
      ensure => directory,
      owner => hdfs,
      group => hdfs,
      mode => 755,
      require => [ Package["hadoop-hdfs"] ],
    }
  }

  define httpfs ($namenode_host, $namenode_port, $port = "14000", $auth = "simple", $secret = "hadoop httpfs secret") {

    $hadoop_namenode_host = $namenode_host
    $hadoop_namenode_port = $namenode_port
    $hadoop_httpfs_port = $port
    $hadoop_security_authentication = $auth

    if ($auth == "kerberos") {
      kerberos::host_keytab { "httpfs":
        spnego => true,
      }
    }

    package { "hadoop-httpfs":
      ensure => latest,
      require => Package["jdk"],
    }

    file { "/etc/hadoop-httpfs/conf/httpfs-site.xml":
      content => template('hadoop/httpfs-site.xml'),
      require => [Package["hadoop-httpfs"]],
    }

    file { "/etc/hadoop-httpfs/conf/httpfs-env.sh":
      content => template('hadoop/httpfs-env.sh'),
      require => [Package["hadoop-httpfs"]],
    }

    file { "/etc/hadoop-httpfs/conf/httpfs-signature.secret":
      content => inline_template("<%= secret %>"),
      require => [Package["hadoop-httpfs"]],
    }

    service { "hadoop-httpfs":
      ensure => running,
      hasstatus => true,
      subscribe => [Package["hadoop-httpfs"], File["/etc/hadoop-httpfs/conf/httpfs-site.xml"], File["/etc/hadoop-httpfs/conf/httpfs-env.sh"], File["/etc/hadoop-httpfs/conf/httpfs-signature.secret"]],
      require => [ Package["hadoop-httpfs"] ],
    }
    Kerberos::Host_keytab <| title == "httpfs" |> -> Service["hadoop-httpfs"]
  }

  class kinit {
    include hadoop::kerberos

    exec { "HDFS kinit":
      command => "/usr/bin/kinit -kt /etc/hdfs.keytab hdfs/$fqdn && /usr/bin/kinit -R",
      user    => "hdfs",
      require => Kerberos::Host_keytab["hdfs"],
    }
  }

  define create_hdfs_dirs($hdfs_dirs_meta, $auth="simple") {
    $user = $hdfs_dirs_meta[$title][user]
    $perm = $hdfs_dirs_meta[$title][perm]

    if ($auth == "kerberos") {
      require hadoop::kinit
      Exec["HDFS kinit"] -> Exec["HDFS init $title"]
    }

    exec { "HDFS init $title":
      user => "hdfs",
      command => "/bin/bash -c 'hadoop fs -mkdir $title && hadoop fs -chmod $perm $title && hadoop fs -chown $user $title'",
      unless => "/bin/bash -c 'hadoop fs -ls $name >/dev/null 2>&1'",
      require => Service["hadoop-hdfs-namenode"],
    }
    Exec <| title == "activate nn1" |>  -> Exec["HDFS init $title"]
  }

  define namenode ($host = $fqdn , $port = "8020", $thrift_port= "10090", $auth = "simple", $dirs = ["/tmp/nn"], $ha = 'disabled') {

    $first_namenode = inline_template("<%= host.to_a[0] %>")
    $hadoop_namenode_host = $host
    $hadoop_namenode_port = $port
    $hadoop_namenode_thrift_port = $thrift_port
    $hadoop_security_authentication = $auth

    if ($ha == 'enabled') {
      $sshfence_user      = extlookup("hadoop_ha_sshfence_user",      "hdfs") 
      $sshfence_user_home = extlookup("hadoop_ha_sshfence_user_home", "/var/lib/hadoop-hdfs")
      $sshfence_keydir    = "$sshfence_user_home/.ssh"
      $sshfence_keypath   = "$sshfence_keydir/id_sshfence"
      $sshfence_privkey   = extlookup("hadoop_ha_sshfence_privkey",   "$extlookup_datadir/hadoop/id_sshfence")
      $sshfence_pubkey    = extlookup("hadoop_ha_sshfence_pubkey",    "$extlookup_datadir/hadoop/id_sshfence.pub")
      $shared_edits_dir   = extlookup("hadoop_ha_shared_edits_dir",   "/hdfs_shared")
      $nfs_server         = extlookup("hadoop_ha_nfs_server",         "")
      $nfs_path           = extlookup("hadoop_ha_nfs_path",           "")

      file { $sshfence_keydir:
        ensure  => directory,
        owner   => 'hdfs',
        group   => 'hdfs',
        mode    => '0700',
        require => Package["hadoop-hdfs"],
      }

      file { $sshfence_keypath:
        source  => $sshfence_privkey,
        owner   => 'hdfs',
        group   => 'hdfs',
        mode    => '0600',
        before  => Service["hadoop-hdfs-namenode"],
        require => File[$sshfence_keydir],
      }

      file { "$sshfence_keydir/authorized_keys":
        source  => $sshfence_pubkey,
        owner   => 'hdfs',
        group   => 'hdfs',
        mode    => '0600',
        before  => Service["hadoop-hdfs-namenode"],
        require => File[$sshfence_keydir],
      }

      file { $shared_edits_dir:
        ensure => directory,
      }

      if ($nfs_server) {
        if (!$nfs_path) {
          fail("No nfs share specified for shared edits dir")
        }

        require nfs::client

        mount { $shared_edits_dir:
          ensure  => "mounted",
          atboot  => true,
          device  => "${nfs_server}:${nfs_path}",
          fstype  => "nfs",
          options => "tcp,soft,timeo=10,intr,rsize=32768,wsize=32768",
          require => File[$shared_edits_dir],
          before  => Service["hadoop-hdfs-namenode"],
        }
      }
    }

    include common-hdfs

    package { "hadoop-hdfs-namenode":
      ensure => latest,
      require => Package["jdk"],
    }

    service { "hadoop-hdfs-namenode":
      ensure => running,
      hasstatus => true,
      subscribe => [Package["hadoop-hdfs-namenode"], File["/etc/hadoop/conf/core-site.xml"], File["/etc/hadoop/conf/hdfs-site.xml"], File["/etc/hadoop/conf/hadoop-env.sh"]],
      require => [Package["hadoop-hdfs-namenode"]],
    } 
    Exec <| tag == "namenode-format" |>         -> Service["hadoop-hdfs-namenode"]
    Kerberos::Host_keytab <| title == "hdfs" |> -> Service["hadoop-hdfs-namenode"]

    if ($::fqdn == $first_namenode) {
      exec { "namenode format":
        user => "hdfs",
        command => "/bin/bash -c 'yes Y | hadoop namenode -format >> /tmp/nn.format.log 2>&1'",
        creates => "${namenode_data_dirs[0]}/current/VERSION",
        require => [ Package["hadoop-hdfs-namenode"], File[$dirs] ],
        tag     => "namenode-format",
      } 
      
      if ($ha == "enabled") {
        exec { "activate nn1":
          command => "/usr/bin/hdfs haadmin -transitionToActive nn1",
          user    => "hdfs",
          unless  => "/usr/bin/test $(/usr/bin/hdfs haadmin -getServiceState nn1) = active",
          require => Service["hadoop-hdfs-namenode"],
        }
      }
    } elsif ($ha == "enabled") {
      hadoop::namedir_copy { $namenode_data_dirs: 
        source       => $first_namenode,
        ssh_identity => $sshfence_keypath,
        require      => File[$sshfence_keypath],
      }
    }

    file {
      "/etc/default/hadoop-hdfs-namenode":
        content => template('hadoop/hadoop-hdfs'),
        require => [Package["hadoop-hdfs-namenode"]],
    }
    
    file { $dirs:
      ensure => directory,
      owner => hdfs,
      group => hdfs,
      mode => 700,
      require => [Package["hadoop-hdfs"]], 
    }
  }

  define namedir_copy ($source, $ssh_identity) {
    exec { "copy namedir $title from first namenode":
      command => "/usr/bin/rsync -avz -e '/usr/bin/ssh -oStrictHostKeyChecking=no -i $ssh_identity' '${source}:$title/' '$title/'",
      user    => "hdfs",
      tag     => "namenode-format",
      creates => "$title/current/VERSION",
    }
  }
      
  define secondarynamenode ($namenode_host, $namenode_port, $port = "50090", $auth = "simple") {

    $hadoop_secondarynamenode_port = $port
    $hadoop_security_authentication = $auth

    include common-hdfs

    package { "hadoop-hdfs-secondarynamenode":
      ensure => latest,
      require => Package["jdk"],
    }

    file {
      "/etc/default/hadoop-hdfs-secondarynamenode":
        content => template('hadoop/hadoop-hdfs'),
        require => [Package["hadoop-hdfs-secondarynamenode"]],
    }

    service { "hadoop-hdfs-secondarynamenode":
      ensure => running,
      hasstatus => true,
      subscribe => [Package["hadoop-hdfs-secondarynamenode"], File["/etc/hadoop/conf/core-site.xml"], File["/etc/hadoop/conf/hdfs-site.xml"], File["/etc/hadoop/conf/hadoop-env.sh"]],
      require => [Package["hadoop-hdfs-secondarynamenode"]],
    }
    Kerberos::Host_keytab <| title == "hdfs" |> -> Service["hadoop-hdfs-secondarynamenode"]
  }


  define resourcemanager ($host = $fqdn, $port = "8040", $rt_port = "8025", $sc_port = "8030", $thrift_port = "9290", $auth = "simple") {
    $hadoop_rm_host = $host
    $hadoop_rm_port = $port
    $hadoop_rt_port = $rt_port
    $hadoop_sc_port = $sc_port
    $hadoop_security_authentication = $auth

    include common-yarn

    package { "hadoop-yarn-resourcemanager":
      ensure => latest,
      require => Package["jdk"],
    }

    service { "hadoop-yarn-resourcemanager":
      ensure => running,
      hasstatus => true,
      subscribe => [Package["hadoop-yarn-resourcemanager"], File["/etc/hadoop/conf/hadoop-env.sh"], 
                    File["/etc/hadoop/conf/yarn-site.xml"], File["/etc/hadoop/conf/core-site.xml"]],
      require => [ Package["hadoop-yarn-resourcemanager"] ],
    }
    Kerberos::Host_keytab <| tag == "mapreduce" |> -> Service["hadoop-yarn-resourcemanager"]
  }

  define proxyserver ($host = $fqdn, $port = "8088", $auth = "simple") {
    $hadoop_ps_host = $host
    $hadoop_ps_port = $port
    $hadoop_security_authentication = $auth

    include common-yarn

    package { "hadoop-yarn-proxyserver":
      ensure => latest,
      require => Package["jdk"],
    }

    service { "hadoop-yarn-proxyserver":
      ensure => running,
      hasstatus => true,
      subscribe => [Package["hadoop-yarn-proxyserver"], File["/etc/hadoop/conf/hadoop-env.sh"], 
                    File["/etc/hadoop/conf/yarn-site.xml"], File["/etc/hadoop/conf/core-site.xml"]],
      require => [ Package["hadoop-yarn-proxyserver"] ],
    }
    Kerberos::Host_keytab <| tag == "mapreduce" |> -> Service["hadoop-yarn-proxyserver"]
  }

  define historyserver ($host = $fqdn, $port = "10020", $webapp_port = "19888", $auth = "simple") {
    $hadoop_hs_host = $host
    $hadoop_hs_port = $port
    $hadoop_hs_webapp_port = $app_port
    $hadoop_security_authentication = $auth

    include common-mapred-app

    package { "hadoop-mapreduce-historyserver":
      ensure => latest,
      require => Package["jdk"],
    }

    service { "hadoop-mapreduce-historyserver":
      ensure => running,
      hasstatus => true,
      subscribe => [Package["hadoop-mapreduce-historyserver"], File["/etc/hadoop/conf/hadoop-env.sh"], 
                    File["/etc/hadoop/conf/yarn-site.xml"], File["/etc/hadoop/conf/core-site.xml"]],
      require => [Package["hadoop-mapreduce-historyserver"]],
    }
    Kerberos::Host_keytab <| tag == "mapreduce" |> -> Service["hadoop-mapreduce-historyserver"]
  }


  define nodemanager ($rm_host, $rm_port, $rt_port, $auth = "simple", $dirs = ["/tmp/yarn"]){
    $hadoop_rm_host = $rm_host
    $hadoop_rm_port = $rm_port
    $hadoop_rt_port = $rt_port

    include common-yarn

    package { "hadoop-yarn-nodemanager":
      ensure => latest,
      require => Package["jdk"],
    }
 
    service { "hadoop-yarn-nodemanager":
      ensure => running,
      hasstatus => true,
      subscribe => [Package["hadoop-yarn-nodemanager"], File["/etc/hadoop/conf/hadoop-env.sh"], 
                    File["/etc/hadoop/conf/yarn-site.xml"], File["/etc/hadoop/conf/core-site.xml"]],
      require => [ Package["hadoop-yarn-nodemanager"], File[$dirs] ],
    }
    Kerberos::Host_keytab <| tag == "mapreduce" |> -> Service["hadoop-yarn-nodemanager"]

    file { $dirs:
      ensure => directory,
      owner => yarn,
      group => yarn,
      mode => 755,
      require => [Package["hadoop-yarn"]],
    }
  }

  define mapred-app ($namenode_host, $namenode_port, $jobtracker_host, $jobtracker_port, $auth = "simple", $jobhistory_host = "", $jobhistory_port="10020", $dirs = ["/tmp/mr"]){
    $hadoop_namenode_host = $namenode_host
    $hadoop_namenode_port = $namenode_port
    $hadoop_jobtracker_host = $jobtracker_host
    $hadoop_jobtracker_port = $jobtracker_port
    $hadoop_security_authentication = $auth

    include common-mapred-app

    if ($jobhistory_host != "") {
      $hadoop_hs_host = $jobhistory_host
      $hadoop_hs_port = $jobhistory_port
    }

    file { $dirs:
      ensure => directory,
      owner => yarn,
      group => yarn,
      mode => 755,
      require => [Package["hadoop-mapreduce"]],
    }
  }

  define client ($namenode_host, $namenode_port, $jobtracker_host, $jobtracker_port, $auth = "simple") {
      $hadoop_namenode_host = $namenode_host
      $hadoop_namenode_port = $namenode_port
      $hadoop_jobtracker_host = $jobtracker_host
      $hadoop_jobtracker_port = $jobtracker_port
      $hadoop_security_authentication = $auth

      include common-mapred-app
  
      # FIXME: "hadoop-source", "hadoop-fuse", "hadoop-pipes"
      package { ["hadoop-doc", "hadoop-debuginfo", "hadoop-libhdfs"]:
        ensure => latest,
        require => [Package["jdk"], Package["hadoop"], Package["hadoop-hdfs"], Package["hadoop-mapreduce"]],  
      }
  }
}
