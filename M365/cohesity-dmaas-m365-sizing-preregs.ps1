### This script will install needed modules to use M365 Sizer tool - Jussi Jaurola <jussi@cohesity.com>


$modules = @("Microsoft.Graph.Reports", "ExchangeOnlineManagement","PSWSMan")

foreach($module in $modules)
{
    Write-Host "Checking module $module" -ForegroundColor Yellow
    if (!(Get-Module -ListAvailable -Name $module)) {
      Write-Host "    Installing module $module" -ForegroundColor Yellow
      Install-Module $module -Scope CurrentUser -Force
      if ($module -eq 'PSWSMan') {
        Write-Host "Module PWSMan requires additional command also. Running Install-WSMan" -ForegroundColor Yellow
        Install-WSMan
      }
    } else {
        Write-Host "   Module found!" -ForegroundColor Yellow
    }
}

Write-Host "NOTE! Please close this PowerShell session and open new to download actual sizer tool and to run it!" -ForegroundColor Yellow
