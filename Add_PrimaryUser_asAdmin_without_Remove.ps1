$Log_File = "c:\windows\debug\Add_local_admin.log"
Function Write_Log {
        param(
        $Message_Type,
        $Message
        )
        
        $MyDate = "[{0:MM/dd/yy} {0:HH:mm:ss}]" -f (Get-Date)
        Add-Content $Log_File  "$MyDate - $Message_Type : $Message"
        write-host  "$MyDate - $Message_Type : $Message"
    }
    
If(!(test-path $Log_File)){new-item $Log_File -type file -force}

$Module_Installed = $False

If(!(Get-Module -listavailable | Where-Object {$_.name -like "*Microsoft.Graph.Authentication*"})) {
        Install-Module Microsoft.Graph.Authentication -ErrorAction SilentlyContinue -Force
        Write_Log -Message_Type "INFO" -Message "Graph Authentication module has been installed"
        $Module_Installed = $True
    }
Else {
        Import-Module Microsoft.Graph.Authentication -ErrorAction SilentlyContinue -Force
        Write_Log -Message_Type "INFO" -Message "Graph Authentication module has been imported"
        $Module_Installed = $True
    }

If(!(Get-Module -listavailable | Where-Object {$_.name -like "*Microsoft.Graph.DeviceManagement*"})) {
        Install-Module Microsoft.Graph.DeviceManagement -ErrorAction SilentlyContinue -Force
        Write_Log -Message_Type "INFO" -Message "Graph Device Management module has been installed"
        $Module_Installed = $True
    }
Else {
        Import-Module Microsoft.Graph.DeviceManagement -ErrorAction SilentlyContinue -Force
        Write_Log -Message_Type "INFO" -Message "Graph Device Management module has been imported"
        $Module_Installed = $True
    }

If($Module_Installed -eq $True) {
        $Intune_Connected = $False
        $tenant = "Your tenant"
        $clientId = "Your client ID"
        $clientSecret = "Your secret"
	$secureClientSecret = ConvertTo-SecureString -String $clientSecret -AsPlainText -Force
        $clientSecretCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $clientId, $secureClientSecret
        Try {
            Connect-MgGraph -TenantId $tenant -ClientSecretCredential $clientSecretCredential -NoWelcome
            Write_Log -Message_Type "SUCCESS" -Message "Connection OK to Intune"
            $Intune_Connected = $True
        }
        Catch {
            Write_Log -Message_Type "ERROR" -Message "Unable to connect to Intune"
        }

        If($Intune_Connected -eq $True) {
                $Device_Found = $False

                Try {
                    $Get_MyDevice_Infos = Get-MgDeviceManagementManagedDevice | Where-Object {$_.DeviceName -eq "$($env:COMPUTERNAME)"}
                    Write_Log -Message_Type "INFO" -Message "Device $env:COMPUTERNAME has been found in Intune"
                    $Device_Found = $True
                }
                Catch {
                    Write_Log -Message_Type "INFO" -Message "Device $env:COMPUTERNAME has not been found in Intune"
                    $Device_Found = $False
                }
                
                If($Device_Found -eq $True) {
                        $Get_MyDevice_ID = $Get_MyDevice_Infos.id
                        Write_Log -Message_Type "INFO" -Message "Device ID is: $Get_MyDevice_ID"

                        $graphApiVersion = "beta"
                        $Resource = "deviceManagement/managedDevices"
                        $uri = "https://graph.microsoft.com/$graphApiVersion/$($Resource)" + "/" + $Get_MyDevice_ID
                        $Get_Primary_User_ID = (Invoke-MgGraphRequest -Uri $uri).userId
                        Write_Log -Message_Type "INFO" -Message "Primary user ID is: $Get_Primary_User_ID"

                        function Convert-ObjectIdToSid {
                            param([String] $ObjectId)
                            $bytes = [Guid]::Parse($ObjectId).ToByteArray()
                            $array = New-Object 'UInt32[]' 4
                            [Buffer]::BlockCopy($bytes, 0, $array, 0, 16)
                            $sid = "S-1-12-1-$array".Replace(' ', '-')
                            return $sid
                        }

                        $Get_SID = Convert-ObjectIdToSid $Get_Primary_User_ID
                        Write_Log -Message_Type "INFO" -Message "Primary user SID is: $Get_SID"

                        $Get_Local_AdminGroup = Get-CimInstance -Class Win32_Group -Filter "Domain='$env:COMPUTERNAME' and SID='S-1-5-32-544'"
                        $Get_Local_AdminGroup_Name = $Get_Local_AdminGroup.Name
                        Write_Log -Message_Type "INFO" -Message "Admin group name is: $Get_Local_AdminGroup_Name"


                        Try {
                            $ADSI = [ADSI]("WinNT://$env:COMPUTERNAME")
                            $Group = $ADSI.Children.Find($Get_Local_AdminGroup_Name, 'group')
                            $Group.Add(("WinNT://$get_sid"))
                            Write_Log -Message_Type "SUCCESS" -Message "$Get_SID has been added in $Get_Local_AdminGroup_Name"
                        }
                        Catch {
                            Write_Log -Message_Type "ERROR" -Message "There was an error detecting user $Get_SID in group $Get_Local_AdminGroup_Name"
                        }
                    }
            }
    }
Else {
        Write_Log -Message_Type "INFO" -Message "Graph Intune module has not been imported"
    }
