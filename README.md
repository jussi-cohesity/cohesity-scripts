# cohesity-scripts - REST API Examples

This repository contains short code examples on how to use Cohesity REST API endpoints.

## Additional repository

Some of these scripts are using Brian Seltzer's cohesity-api.ps1. You can get it and guide to it from https://github.com/bseltz-cohesity/scripts/tree/master/powershell

Others leverage Cohesity PowerShell Module which can be found from https://cohesity.github.io/cohesity-powershell-module/#/

## API Authentication

You can automate running scripts with integrated authentication. There are two methods used in these scripts. Scripts using Brian's cohesity-api.ps1 has integrated method to store authentication keys. Without this scripts using Cohesity PowerShell module will always ask authentication when running script.

With scripts using Cohesity powerShell Module you can use PSCredentialTools (https://www.powershellgallery.com/packages/PSCredentialTools/1.0.1). After installing you can create new credentials with

```
Export-PSCredential -Path ./cohesityCredential.json -SecureKey ('$ecretK3y4salt1ng' | Convertto-SecureString -AsPlainText -Force)
```

After this you can use credentials by importing them from file and using them when connecting to cluster
```
$credentials = Import-PSCredential -Path ./cohesityCredential.json -SecureKey ('$ecretK3y4salt1ng' | Convertto-SecureString -AsPlainText -Force)

Connect-CohesityCluster -server <ip> -Credential $credentials
```

## Notes
This is not an official Cohesity repository. Cohesity Inc. is not affiliated with the posted examples in any way.

```
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
```

You can contact me via email (firstname AT cohesity.com)
