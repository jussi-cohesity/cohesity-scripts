# Cohesity VMware file restore test example

This is an example powershell for simple file recovery test for VMware Protection Job.

# Prerequisites

* [PowerShell](https://aka.ms/getps6)
* [Cohesity PowerShell Module](https://cohesity.github.io/cohesity-powershell-module/#/)

# How to start using this?


## Credential files

This script uses encrypted credentials for authentication. You can create credentials with simple two commands:

```PowerShell
Get-Credential | Export-Clixml server_credentials.xml
Get-Credential | Export-Clixml cohesity_credentials.xml
```

Note: Secure XML files can only be decrypted by the user account that created them.

## Usage
./cohesity-vmware-filerecovery.ps1 -cohesity -cohesityCluster 192.168.1.198 -cohesityCred 'cohesity_credentials.xml' -serverCred 'vmware_credentials.xml' -filename '/C/data/file.txt' -newdir 'C:/temp/recovery/' -server 'windows-virtual'


# Notes
Jussi Jaurola - <jussi@cohesity.com>
```
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
```
