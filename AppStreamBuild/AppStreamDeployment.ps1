#####################################################################################################################################
#AppStream2.0 automation script
#
#The script performs the following tasks:
#1.Creates a directory config - only if the directory config does not exist.
#2.Deploys a Image Builder - deleted upon successful creation of the snapshot.
#3.Launches pre-signed Image Builder URL from the Internet Explore browser.
#4.Createes a custom image from the Image Builder.
#5.Creates a fleet.
#6.Starts up the fleet.
#7.Creates a stack.
#8.Associates the stack with the fleet.
#
#Image Builder domain join is hashed out, requires testing.
#####################################################################################################################################


################################################
#Parameters
################################################
#Directory
$DirectoryName="corp.com" #Name of the directory. It can be an existing or new directory
$ServiceAccount="corp\dadmin" #Directory service account
$pw="Password123" #Service password
$OU="OU=appstream,DC=corp,DC=com" #New OU path for the new fleet. This OU has already created in AD in the previous CFN script #No spaces

#Image builder
$ImageBuilderName="ExampleBuilder" #Name of the image builder
$ImageName="Base-Image-Builder-01-24-2018" #Public image
$ImageBuilderInstanceType="stream.standard.medium"
$ImageBuilderSG="sg-4da4b934" #Security group ID that the image builder will be attached to. This security group is already created as part of Part2AD stack. See the stack output DomainMemberSGID.
$ImageBuilderSub="subnet-0729054e" #subnet ID which the image builder will be deployed into. This security group is already created as part of Part1VPC stack. See the stack output PrivSub3ID.
$OU="OU=appstream,DC=corp,DC=com"

#Fleet
$FleetName="ExampleFleet" #Name of the new fleet
$FleetInstanceType="stream.standard.medium" #Instance size
$FleetType="ALWAYS_ON" #Fleet type ALWAYS_ON or ON_DEMAND
$ComputeCapacity="2"
$FleetSG="sg-4da4b934" #Security group ID that the fleet will be attached to. This security group is already created as part of Part2AD stack. See the stack output DomainMemberSGID.
$FleetSub="subnet-0729054e" #subnet ID which the fleet will be deployed into. This is the service subnet.This security group is already created as part of Part1VPC stack. See the stack output PrivSub3ID.
$DisconnectTimeoutInSecond="57600" #The time after disconnection when a session is considered to have ended, in seconds. If a user who was disconnected reconnects within this time interval, the user is connected to their previous session. Specify a value between 60 and 57600.
#Stack
$StackName="ExampleStack" #Name of the new stack
$GoldImageName="ExampleImage" #The variable must match the image name which provided to the image assistant by the user.

#Storage
$Storage="" #Leave this blank if there is no existing storage available.
# 'appstream2-36fb080bb8-ap-northeast-1-953054109197'
################################################
#Main function
################################################
Function Start-Commands {
  Directory
  ImageBuilder
      FleetCreate
    StackCreate
    AssociateStackFleet
}


################################################
#Image builder function
################################################
Function ImageBuilder {
    ImageBuilderDeploy
    ImageBuilderConfig

}

################################################
#IE Browser for image assistant
################################################
Function LaunchBrowser ($urlval) {
    $IE=new-object -com internetexplorer.application
     $IE.Navigate2("$urlval")
     $IE.visible=$true
    }

################################################
#Directory Config
################################################
Function Directory() {

 $tempD = Get-APSDirectoryConfigList | Select-object -Property DirectoryName |  Where-Object {$_.DirectoryName -Match $DirectoryName}

    if ($tempD.DirectoryName -eq $DirectoryName) {
        $eOU=@(Get-APSDirectoryConfigList -DirectoryName $DirectoryName |%{$_.OrganizationalUnitDistinguishedNames}) #Existing OU/OUs

        $NewOU =$eOU += $OU
        $NewOU.GetType()

       # $eOU = $eOU -join '","'
       # $dinal = '"'+$eOU +'"'+',"'+$OU+'"'
       # write-host "$dinal"

        Update-APSDirectoryConfig -DirectoryName $DirectoryName -OrganizationalUnitDistinguishedName $NewOU
     Write-Host "Directory already exists. Directory Config up to date." -ForegroundColor Cyan
     } else {
       New-APSDirectoryConfig -DirectoryName $DirectoryName -OrganizationalUnitDistinguishedName $OU -ServiceAccountCredentials_AccountName $ServiceAccount -ServiceAccountCredentials_AccountPassword $pw
       Write-Host "New Directory $DirectoryName created." -ForegroundColor Cyan
       }

}

################################################
#Image builder deployment
################################################
Function ImageBuilderDeploy() {
    Try {
        New-APSImageBuilder -name $ImageBuilderName -ImageName $ImageName -instancetype $ImageBuilderInstanceType -VpcConfig_SecurityGroupId $ImageBuilderSG -VpcConfig_SubnetId $ImageBuilderSub #-DomainJoinInfo_DirectoryName $DirectoryName -DomainJoinInfo_OrganizationalUnitDistinguishedName $ImageBuilderOU
        $IBState = Get-APSImageBuilderList -Name $ImageBuilderName |%{$_.State.Value}

        if ($IBState) {write-host "Launching image builder......"-ForegroundColor Cyan}
        Sleep 100

        while ($IBState -notmatch 'RUNNING') {
        $IBState = Get-APSImageBuilderList -Name $ImageBuilderName |%{$_.State.Value}
            if ($IBState -match 'PENDING') {
                write-host "Launching image builder......"-ForegroundColor Cyan
                sleep 90
                #break
            } elseif ($IBState -match 'FAILED' -or $IBState -match 'REBOOTING' -or $IBState -match 'DELETING') {
               Write-Host "Image Builder failed to launch. State: $IBState " -ForegroundColor yellow
               exit(1)
            }
        }
        Write-Host "Image Builder deployed." -ForegroundColor cyan

    } catch {
        write-host "Failed to create Image Builder $ImageBuilderName" -ForegroundColor Magenta
        exit(1)
    }
}

################################################
#Image builder configuration
################################################
Function ImageBuilderConfig() {
    Try {
        Write-Host "Check your IE browser to access AppStream2.0 Image Builder. Click on the Image Assistant on the desktop to finalise the build process. The script will continue once you click on ""Disconnect"" from the Image Assistant. Name the image $GoldImageName." -ForegroundColor yellow
        $urllink = New-APSImageBuilderStreamingURL -name $ImageBuilderName  |%{$_.StreamingURL}
        #Write-Host "$urllink"
       LaunchBrowser $urllink
        #AT THIS POINT IT IS IN RUNNING STATE
        #Image name is provided during the Image Assistant
        #Waiting user compelte the image assistant
        sleep 10
        $IBState = Get-APSImageBuilderList -Name $ImageBuilderName |%{$_.State.Value}
        #write-host "Status $IBState"
        while ($IBState -match 'RUNNING' -or $IBState -match 'SNAPSHOTTING' -or $IBState -match 'STOPPED' -or $IBState -match 'REBOOTING' -or $IBState -match 'STOPPING' -or $IBState -match 'PENDING') {
            $IBState = Get-APSImageBuilderList -Name $ImageBuilderName |%{$_.State.Value}
            if ($IBState -match 'STOPPED') {
                Sleep 60
                Write-Host "Gold image $GoldImageName created successfully." -ForegroundColor cyan
               Remove-APSImageBuilder -name $ImageBuilderName -force
                Write-Host "Image builder $ImageBuilderName deleted." -ForegroundColor cyan
                sleep 2
                break
            } elseif ($IBState -match 'RUNNING') {
                Write-Host "Waiting on user to complete the image build...." -ForegroundColor Yellow
                Sleep 60
                $IBState = Get-APSImageBuilderList -Name $ImageBuilderName |%{$_.State.Value}
                #break
            } elseif ($IBState -match 'SNAPSHOTTING' -or $IBState -match 'REBOOTING' -or $IBState -match 'STOPPING' -or $IBState -match 'PENDING') {
                Write-Host "Snapshotting image...." -ForegroundColor cyan
                Sleep 60
                $IBState = Get-APSImageBuilderList -Name $ImageBuilderName |%{$_.State.Value}
                #break
            } else {
                write-host "Failed to build the image." -ForegroundColor Magenta
                exit(1)
            }
        }
    } Catch {
        write-host "Image builder config failed." -ForegroundColor Magenta
        exit(1)
    }
}



################################################
#Fleet creation
################################################
Function FleetCreate() {
    Try {
        #Create a new fleet

        New-APSFleet -Name $FleetName -ImageName $GoldImageName -InstanceType $FleetInstanceType -FleetType $FleetType -ComputeCapacity_DesiredInstance $ComputeCapacity -VpcConfig_SecurityGroupId $FleetSG -VpcConfig_SubnetId $FleetSub -DomainJoinInfo_DirectoryName $DirectoryName -DomainJoinInfo_OrganizationalUnitDistinguishedName $OU -DisconnectTimeoutInSecond $DisconnectTimeoutInSecond
        #Domain join might not work in demo see if fleet throws errors
        Sleep 5
        Start-APSFleet -Name $FleetName
        Sleep 5
        $FStatus = Get-APSFleetList -Name $FleetName |%{$_.State.Value}
        While ($FStatus -match 'STARTING') {
            $FStatus = Get-APSFleetList -Name $FleetName |%{$_.State.Value}
            Write-Host "Starting fleet $FleetName...."
            Sleep 60
        }
    } catch {
        write-host "Failed to create fleet $FleetName." -ForegroundColor Magenta
        exit(1)
    }
}


################################################
#Stack creation
################################################
Function StackCreate() {
    Try {
        #New-APSStack -Name $StackName -StorageConnector ConnectorType(HOMEFOLDERS) ResourceIdentifier(appstream2-36fb080bb8-ap-northeast-1-953054109197)
        $StorageConnector = New-Object -TypeName 'Amazon.AppStream.Model.StorageConnector'
$StorageConnector.ConnectorType = [Amazon.AppStream.StorageConnectorType]::HOMEFOLDERS
$StorageConnector.ResourceIdentifier = $Storage

        New-APSStack -Name $StackName #-StorageConnector $StorageConnector
        write-host "$StackName created." -ForegroundColor Cyan
    } catch {
        write-host "Failed to create stack $StackName." -ForegroundColor Magenta
        exit(1)
    }
}


################################################
#Associate fleet with stack
################################################
Function AssociateStackFleet() {
    Try {
        Register-APSFleet -StackName $StackName -FleetName $FleetName -Force
        write-host "Stack $StackName associated with fleet $FleetName." -ForegroundColor cyan
        Start-APSFleet -Name $FleetName -Force
        write-host "Fleet $FleetName started." -ForegroundColor cyan
    } catch {
        write-host "Failed to associate $StackName with $FleetName." -ForegroundColor Magenta
        exit(1)
    }
}



################################################
#Start of the script
################################################
Write-Host "STARTED SCRIPT`r`n" -ForegroundColor Green -BackgroundColor DarkGreen
Start-Commands
Write-Host "STOPPED SCRIPT" -ForegroundColor Green -BackgroundColor DarkGreen

#IAM
