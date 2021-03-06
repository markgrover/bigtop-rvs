/**
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements.  See the NOTICE file
 * distributed with this work for additional information
 * regarding copyright ownership.  The ASF licenses this file
 * to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License.  You may obtain a copy of the License at
 * <p/>
 * http://www.apache.org/licenses/LICENSE-2.0
 * <p/>
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package org.apache.bigtop.itest.shell

import org.junit.Ignore
import org.junit.Test

import static org.junit.Assert.assertEquals
import static org.junit.Assert.assertFalse
import static org.junit.Assert.assertTrue

class ShellTest {
  @Test
  void regularUserShell() {
    Shell sh = new Shell("/bin/bash -s")

    sh.exec('A=a ; r() { return $1; } ; echo $A ; r `id -u`')

    assertFalse("${sh.script} exited with a non-zero status", sh.ret == 0)
    assertEquals("got wrong stdout ${sh.out}", "a", sh.out[0])
    assertEquals("got extra stderr ${sh.err}", 0, sh.err.size())
  }

  @Ignore("requires sudo")
  @Test
  void superUserShell() {
    Shell sh = new Shell("/bin/bash -s")

    sh.setUser('root')
    sh.exec('r() { return $1; } ; r `id -u`')

    assertEquals("${sh.script} exited with a non-zero status", 0, sh.ret)
    assertEquals("got extra stdout ${sh.out}", 0, sh.out.size())
    assertEquals("got extra stderr ${sh.err}", 0, sh.err.size())
  }

  @Test
  void testRegularShellWithTimeout() {
    Shell sh = new Shell("/bin/bash -s")
    def preTime = System.currentTimeMillis()
    sh.execWithTimeout(500, 'A=a ; sleep 30 ; r() { return $1; } ; echo $A ; ' +
      'r `id -u`')
    assertTrue(System.currentTimeMillis() - preTime < 30000)
  }

  @Test
  void testBackgroundExecWithTimeoutFailure() {
    Shell sh = new Shell("/bin/bash -s")
    def preTime = System.currentTimeMillis()
    sh.forkWithTimeout(500, 'A=a ; sleep 30 ; r() { return $1; } ' +
      '; echo $A ; r `id -u`')
    //Wait for script to get killed
    Thread.sleep(750)
    assertTrue("got wrong stdout ${sh.out}", sh.out.isEmpty())
    assertTrue("got wrong srderr ${sh.out}", sh.err.isEmpty())
  }

  @Test
  void testForkWithTimeoutSuccess() {
    Shell sh = new Shell("/bin/bash -s")
    def preTime = System.currentTimeMillis()
    sh.forkWithTimeout(30000,
      'A=a ; r() { return $1; } ; echo $A ; r `id -u`')
    //Wait for the script to complete
    Thread.sleep(500)
    assertFalse("${sh.script} exited with a non-zero status", sh.ret == 0)
    assertEquals("got wrong stdout ${sh.out}", "a", sh.out[0])
    assertEquals("got extra stderr ${sh.err}", 0, sh.err.size())
  }

  @Test
  void testForkWithoutTimeoutSuccess() {
    Shell sh = new Shell("/bin/bash -s")
    sh.fork('A=a ; r() { return $1; } ; echo $A ; r `id -u`')
    //Wait for the script to complete
    Thread.sleep(550)
    assertFalse("${sh.script} exited with a non-zero status", sh.ret == 0)
    assertEquals("got wrong stdout ${sh.out}", "a", sh.out[0])
    assertEquals("got extra stderr ${sh.err}", 0, sh.err.size())
  }
}
