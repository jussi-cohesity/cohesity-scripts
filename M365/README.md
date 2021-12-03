# M365 Sizer Tool

This tool will help you size M365 workloads for both on-prem Cohesity DataProtect and Cohesity DMaaS DataProtect. 

# Prerequisites

* [PowerShell](https://aka.ms/getps6)

## Usage

### Download scripts

Run these commands from PowerShell to download the module installation helper and run it first:

```powershell
# Download pre-script to install required modules
$moduleInstallURL = 'https://raw.githubusercontent.com/jussi-cohesity/cohesity-scripts/master/M365/cohesity-dmaas-m365-sizing-preregs.ps1'
$sizerScriptURL = 'https://raw.githubusercontent.com/jussi-cohesity/cohesity-scripts/master/M365/cohesity-dmaas-m365-sizing.ps1'

(Invoke-WebRequest -Uri "$moduleInstallURL").content | Out-File "cohesity-dmaas-m365-sizing-preregs.ps1"; (Get-Content "cohesity-dmaas-m365-sizing-preregs.ps1") | Set-Content "cohesity-dmaas-m365-sizing-preregs.ps1"

(Invoke-WebRequest -Uri "$sizerScriptURL").content | Out-File "cohesity-dmaas-m365-sizing.ps1"; (Get-Content "ccohesity-dmaas-m365-sizing.ps1") | Set-Content "cohesity-dmaas-m365-sizing.ps1"

. ./cohesity-dmaas-m365-sizing-preregs.ps1
```

Next copy-paste these to PowerShell window to launch actual sizer. Note sizer will open your browser and ask you to authenticate to M365 portal twice. This is because script uses two different integrations and both require their own authentication. This script just connects to your M365 account for reporting download use.

```powershell
# Download Commands
$apiRepoURL = 'https://raw.githubusercontent.com/bseltz-cohesity/scripts/master/powershell'
$repoURL = 'https://raw.githubusercontent.com/jussi-cohesity/cohesity-scripts/master/reporting/cohesity-license-consumers'
(Invoke-WebRequest -Uri "$repoUrl/cohesity-license-consumers.ps1").content | Out-File "cohesity-license-consumers.ps1"; (Get-Content "cohesity-license-consumers.ps1") | Set-Content "cohesity-license-consumers.ps1"

(Invoke-WebRequest -Uri "$apiRepoUrl/cohesity-api/cohesity-api.ps1").content | Out-File cohesity-api.ps1; (Get-Content cohesity-api.ps1) | Set-Content cohesity-api.ps1
# End Download Commands
```

# Other Cohesity M365 example scripts

# Prerequisites in general 

* [PowerShell](https://aka.ms/getps6)
* [Cohesity PowerShell Module](https://cohesity.github.io/cohesity-powershell-module/#/)

# How to start using these scripts? 

## Credential files

This script uses encrypted credentials for authentication. You can create credentials with simple two commands:

```PowerShell
Get-Credential | Export-Clixml cohesity_credentials.xml
```

Note: Secure XML files can only be decrypted by the user account that created them.

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
