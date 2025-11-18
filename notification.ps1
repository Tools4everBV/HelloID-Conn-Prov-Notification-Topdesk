#####################################################
# HelloID-Conn-Prov-Notification-Topdesk
#
# Version: 1.2.0
#####################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Set debug logging
switch ($($actionContext.Configuration.IsDebug)) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}

$account = @{
    TopdeskAssets = "'Query linked assets' checkbox is disabled" # Default message shown when using $account.TopdeskAssets
}

#region functions
function Set-AuthorizationHeaders {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Username,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $ApiKey
    )
    # Create basic authentication string
    $bytes = [System.Text.Encoding]::ASCII.GetBytes("${Username}:${Apikey}")
    $base64 = [System.Convert]::ToBase64String($bytes)

    # Set authentication headers
    $authHeaders = [System.Collections.Generic.Dictionary[string, string]]::new()
    $authHeaders.Add("Authorization", "BASIC $base64")
    $authHeaders.Add('Accept', 'application/json; charset=utf-8')
    $authHeaders.Add('Partner-Solution-Id', 'TOOL001') # Fixed value - Tools4ever Partner Solution ID

    Write-Output $authHeaders
}

function Invoke-TopdeskRestMethod {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Method,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Uri,

        [object]
        $Body,

        [string]
        $ContentType = 'application/json; charset=utf-8',

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]
        $Headers
    )
    process {
        try {
            $splatParams = @{
                Uri         = $Uri
                Headers     = $Headers
                Method      = $Method
                ContentType = $ContentType
            }

            if ($Body) {
                $splatParams['Body'] = [Text.Encoding]::UTF8.GetBytes($Body)
            }

            Invoke-RestMethod @splatParams -Verbose:$false
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }
}

function Get-TopdeskTemplateById {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $BaseUrl,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]
        $Headers,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]
        $Id
    )

    $splatParams = @{
        Uri     = "$baseUrl/tas/api/applicableChangeTemplates"
        Method  = 'GET'
        Headers = $Headers
    }
    $responseGet = Invoke-TopdeskRestMethod @splatParams

    $topdeskTemplate = $responseGet.results | Where-Object { ($_.number -eq $Id) }

    if ([string]::IsNullOrEmpty($topdeskTemplate)) {
        $errorMessage = "Topdesk template [$Id] not found. Please verify this template exists and it's available for the API in Topdesk."
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Message = $errorMessage
                IsError = $true
            })
        return
    }
    
    Write-Output $topdeskTemplate.id
}

function Confirm-Description {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]
        $Description,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]
        $AttributeName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]
        $AllowedLength
    )
    if ($Description.Length -gt $AllowedLength) {
        Write-Verbose "The attribute [$AttributeName] exceeds the max amount of [$AllowedLength] characters [$Description]. The attribute will be shortened"
        $descriptionShortened = $Description.substring(0, [System.Math]::Min($AllowedLength, $Description.Length))
        return $descriptionShortened
    }
    else {
        return $Description
    }
}

function Convert-To-HTML-Tag {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]
        $Description
    )
    $Description = $Description | ConvertTo-Json
    $Description = $Description.Replace('\n', '<br>')
    $Description = $Description | ConvertFrom-Json
    Write-Output $Description
}

function Get-TopdeskPersonByCorrelationAttribute {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $BaseUrl,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]
        $Headers,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]
        $Requester,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]
        $CorrelationAttribute
    )

    # Check if the correlationAttribute is not empty
    if ([string]::IsNullOrEmpty($requester)) {
        $errorMessage = "The correlation attribute [$CorrelationAttribute] is empty. This is likely a scripting issue."
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Message = $errorMessage
                IsError = $true
            })
        return
    }

    # Lookup value is filled in, lookup value in Topdesk
    $splatParams = @{
        Uri     = "$baseUrl/tas/api/persons?page_size=2&query=$($correlationAttribute)=='$($requester)'"
        Method  = 'GET'
        Headers = $Headers
    }
    $responseGet = Invoke-TopdeskRestMethod @splatParams

    # Check if only one result is returned
    if ([string]::IsNullOrEmpty($responseGet.id)) {
        # no results found
        $errorMessage = "Could not set requester: Topdesk person with [$CorrelationAttribute] [$($requester)] not found."
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Message = $errorMessage
                IsError = $true
            })
        return
    }
    elseif ($responseGet.Count -eq 1) {
        # one record found, correlate, return user
        write-output $responseGet
    }
    else {
        # Multiple records found, correlation
        $errorMessage = "Multiple [$($responseGet.Count)] requesters found with [$CorrelationAttribute] [$($requester)]. Login names: [$($responseGet.tasLoginName -join ', ')]"
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Message = $errorMessage
                IsError = $true
            })
    }
}

function Get-TopdeskChangeType {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]
        $changeType # 'simple' or 'extensive'
    )

    # Show audit message if type is empty
    if ([string]::IsNullOrEmpty($changeType)) {
        $errorMessage = "The change type is not set. It should be set to 'simple' or 'extensive'"
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Message = $errorMessage
                IsError = $true
            })
        return
    }

    # Show audit message if type is not 
    if (-not ($changeType -eq 'simple' -or $changeType -eq 'extensive')) {
        $errorMessage = "The configured change type [$changeType] is invalid. It should be set to 'simple' or 'extensive'"
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Message = $errorMessage
                IsError = $true
            })
        return
    }

    return $ChangeType.ToLower()
}

function Get-TopdeskIdentifier {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $BaseUrl,
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]
        $Headers, 
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Class,    
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [Object]
        $Value,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [Object]
        $Endpoint,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [Object]
        $SearchAttribute
    )

    # Check if property exists in the template object set in the mapping
    if (-not($actionContext.TemplateConfiguration.PSobject.Properties.Name -Contains $Class)) {
        $errorMessage = "Requested to lookup [$Class], but the [$Value] parameter is missing in the template file"
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Message = $errorMessage
                IsError = $true
            })
        return
    }
    
    Write-Verbose "Class [$class]: Variable [$`Value] has value [$($Value)] and endpoint [$($Endpoint)?query=$($SearchAttribute)==$($Value))]"

    # Lookup Value is filled in, lookup value in Topdesk
    $splatParams = @{
        Uri     = $baseUrl + $Endpoint + "?query=" + $SearchAttribute + "==" + "'$Value'"
        Method  = 'GET'
        Headers = $Headers
    }
    $responseGet = Invoke-TopdeskRestMethod @splatParams

    $result = $responseGet | Where-object $SearchAttribute -eq $Value

    # When attribute $Class with $Value is not found in Topdesk
    if ([string]::IsNullOrEmpty($result.id)) {
        $errorMessage = "Class [$Class] with SearchAttribute [$SearchAttribute] with value [$Value] isn't found in Topdesk"
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Message = $errorMessage
                IsError = $true
            }) 
    }
    else {
        # $id is found in Topdesk, set in Topdesk
        Write-Output $result.id
    }
}

function Set-TopdeskPersonArchiveStatus {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $BaseUrl,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]
        $Headers,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [Object]
        [Ref]$TopdeskPerson,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [Bool]
        $Archive,

        [Parameter()]
        [String]
        $ArchivingReason
    )

    # Set ArchiveStatus variables based on archive parameter
    if ($Archive -eq $true) {
        #When the 'archiving reason' setting is not configured in the target connector configuration
        if ([string]::IsNullOrEmpty($ArchivingReason)) {
            $errorMessage = "Configuration setting 'Archiving Reason' is empty. This is a configuration error."
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = $errorMessage
                    IsError = $true
                })
            Throw "Error(s) occured while looking up required values"
        }

        $splatParams = @{
            Uri     = "$baseUrl/tas/api/archiving-reasons"
            Method  = 'GET'
            Headers = $Headers
        }

        $responseGet = Invoke-TopdeskRestMethod @splatParams
        $archivingReasonObject = $responseGet | Where-object name -eq $ArchivingReason

        #When the configured archiving reason is not found in Topdesk
        if ([string]::IsNullOrEmpty($archivingReasonObject.id)) {
            $errorMessage = "Archiving reason [$ArchivingReason] not found in Topdesk"
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = $errorMessage
                    IsError = $true
                })
            Throw "Error(s) occured while looking up required values"
        }
        $archiveStatus = 'personArchived'
        $archiveUri = 'archive'
        $body = @{ id = $archivingReasonObject.id }
    }
    else {
        $archiveStatus = 'person'
        $archiveUri = 'unarchive'
        $body = $null
    }

    # Check the current status of the Person and compare it with the status in archiveStatus
    if ($archiveStatus -ne $TopdeskPerson.status) {

        # Archive / unarchive person
        Write-Verbose "[$archiveUri] person with id [$($TopdeskPerson.id)]"
        $splatParams = @{
            Uri     = "$BaseUrl/tas/api/persons/id/$($TopdeskPerson.id)/$archiveUri"
            Method  = 'PATCH'
            Headers = $Headers
            Body    = $body | ConvertTo-Json
        }
        $null = Invoke-TopdeskRestMethod @splatParams
        $TopdeskPerson.status = $archiveStatus
    }
}

function New-TopdeskIncident {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $BaseUrl,
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]
        $Headers,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [PsObject]
        $TopdeskIncident
    )
    $splatParams = @{
        Uri     = "$BaseUrl/tas/api/incidents"
        Method  = 'POST'
        Headers = $Headers
        Body    = $TopdeskIncident | ConvertTo-Json
    }
    #Write-Verbose ($TopdeskIncident | ConvertTo-Json)
    $incident = Invoke-TopdeskRestMethod @splatParams
    Write-Output $incident
}

function New-TopdeskChange {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $BaseUrl,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]
        $Headers,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [PsObject]
        $TopdeskChange
    )

    $splatParams = @{
        Uri     = "$BaseUrl/tas/api/operatorChanges"
        Method  = 'POST'
        Headers = $Headers
        Body    = $TopdeskChange | ConvertTo-Json
    }
    Write-Verbose ($TopdeskChange | ConvertTo-Json)
    $change = Invoke-TopdeskRestMethod @splatParams

    Write-Verbose "Created change with number [$($change.number)]"

    Write-Output $change
}

function Get-VariablesFromString {
    param(
        [string]
        $string
    )
    $regex = [regex]'\$\((.*?)\)'
    $variables = [System.Collections.Generic.list[object]]::new()

    $match = $regex.Match($string)
    while ($match.Success) {
        $variables.Add($match.Value)
        $match = $match.NextMatch()
    }

    Write-Output $variables
}

function Resolve-Variables {
    param(
        [ref]
        $String,

        $VariablesToResolve
    )
    foreach ($var in $VariablesToResolve | Select-Object -Unique) {
        ## Must be changed When changing the the way of lookup variables.
        $varTrimmed = $var.trim('$(').trim(')')
        $Properties = $varTrimmed.Split('.')

        $curObject = (Get-Variable ($Properties | Select-Object -First 1)  -ErrorAction SilentlyContinue).Value
        $Properties | Select-Object -Skip 1 | ForEach-Object {
            if ($_ -ne $Properties[-1]) {
                $curObject = $curObject.$_
            }
            elseif ($null -ne $curObject.$_) {
                $String.Value = $String.Value.Replace($var, $curObject.$_)
            }
            else {
                Write-Verbose  "Variable [$var] not found"
                $String.Value = $String.Value.Replace($var, $curObject.$_) # Add to override unresolved variables with null
            }
        }
    }
}

function Format-Description {
    param (
        [ValidateNotNullOrEmpty()]
        [string]
        $Description
    )
    try {
        $variablesFound = Get-VariablesFromString -String $Description
        Resolve-Variables -String ([ref]$Description) -VariablesToResolve $variablesFound

        Write-Output $Description
    }
    catch {
        Throw $_
    }
}

function Get-TopdeskAssetsByPersonId {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $BaseUrl,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]
        $Headers,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]
        $PersonId,

        [Parameter()]
        [Array]
        $AssetFilter,
        
        [Parameter()]
        [Boolean]
        $SkipNoAssets
    )

    # Check if the correlationAttribute is not empty
    if ([string]::IsNullOrEmpty($PersonId)) {
        $errorMessage = "The person ID [$PersonId] is empty. This is likely a scripting issue."
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Message = $errorMessage
                IsError = $true
            })
        return
    }

    if ($AssetFilter) {
        foreach ($item in $AssetFilter) {
            # Lookup value is filled in, lookup value in Topdesk
            $splatParams = @{
                Uri     = "$baseUrl/tas/api/assetmgmt/assets?archived='false'&templateName=$item&linkedTo=person/$PersonId"
                Method  = 'GET'
                Headers = $Headers
            }

            $responseGet = Invoke-TopdeskRestMethod @splatParams

            # Check if no results are returned
            if ($responseGet.dataSet.Count -gt 0) {
                # records found, filter out archived assets and return
                foreach ($asset in $responseGet.dataSet) {
                    $assetList += "- $($asset.text)`n" # for incidents `n (line break) is automatically converted to <br>
                }
            }
        }   
    }
    else {
        # Lookup value is filled in, lookup value in Topdesk
        $splatParams = @{
            Uri     = "$baseUrl/tas/api/assetmgmt/assets?archived='false'&linkedTo=person/$PersonId"
            Method  = 'GET'
            Headers = $Headers
        }

        $responseGet = Invoke-TopdeskRestMethod @splatParams

        # Check if no results are returned
        if ($responseGet.dataSet.Count -gt 0) {
            # records found, filter out archived assets and return
            foreach ($asset in $responseGet.dataSet) {
                $assetList += "- $($asset.text)`n" # for incidents `n (line break) is automatically converted to <br>
            }
              
        }
    }

    if ([string]::IsNullOrEmpty($assetList)) {
        if ($SkipNoAssets) {
            Write-Verbose 'Action skipped because no assets are found and [SkipNoAssetsFound = true] is configured'
            return
        }
        else {
            # no results found
            $defaultMessage = $actionContext.Configuration.messageNoAssetsFound
            $assetList = "- $defaultMessage`n" # for incidents `n (line break) is automatically converted to <br>
        }
    }
    write-output $assetList
}
function ConvertDifferencesTo-Html {
    [CmdletBinding()]
    param (
        [ValidateNotNullOrEmpty()]
        [string]
        $Description
    )

    $differences = '<br>&nbsp;<br><strong style="font-size : 1.5 em">Difference</strong><br>'
    foreach ($difference in $actionContext.Differences) {
        $differences += "<strong>$($difference.property)</strong> from '<i>$($difference.oldValue)</i>' to '<i>$($difference.newValue)</i>'<br><br>"
    }
    $result = $Description + $differences
    return $result
}

function ConvertDifferencesTo-Text {
    [CmdletBinding()]
    param (
        [ValidateNotNullOrEmpty()]
        [string]
        $Description
    )
    $differences = '
    
Difference 
'
    foreach ($difference in $actionContext.Differences) {
        $differences += "$($difference.property) from '$($difference.oldValue)' to '$($difference.newValue)'
        
"
    }
    $result = $Description + $differences
    return $result
}


#endregion functions

try {
    #region lookup global
    # Setup authentication headers
    $authHeaders = Set-AuthorizationHeaders -UserName $actionContext.Configuration.username -ApiKey $actionContext.Configuration.apiKey

    #requester
    $splatParamsTopdesk = @{
        Requester            = $actionContext.TemplateConfiguration.TopdeskPerson
        CorrelationAttribute = $actionContext.TemplateConfiguration.TopdeskPersonCorrelation
        Headers              = $authHeaders
        BaseUrl              = $actionContext.Configuration.baseUrl
    }

    $TopdeskPerson = Get-TopdeskPersonByCorrelationAttribute @splatParamsTopdesk

    # Lookup Assets of person   
    if ($actionContext.TemplateConfiguration.enableGetAssets) {
        if ($TopdeskPerson.employeeNumber -eq $personContext.Person.ExternalId) {
            $TopdeskPersonForAssets = $TopdeskPerson
        }
        else {
            $splatParamsTopdeskEmployee = @{
                Requester            = $personContext.Person.ExternalId
                CorrelationAttribute = 'employeeNumber'
                Headers              = $authHeaders
                BaseUrl              = $actionContext.Configuration.baseUrl
            }

            $TopdeskPersonForAssets = Get-TopdeskPersonByCorrelationAttribute @splatParamsTopdeskEmployee
        }
    
        if (-not[string]::IsNullOrEmpty($($TopdeskPersonForAssets.Id))) {
            # get assets of employee
            $splatParamsTopdeskAssets = @{
                PersonId     = $TopdeskPersonForAssets.Id
                Headers      = $authHeaders
                BaseUrl      = $actionContext.Configuration.baseUrl
                AssetFilter  = $($actionContext.TemplateConfiguration.assetsFilter).Split("`n") #TemplateName, case sensitive
                SkipNoAssets = [boolean]$actionContext.TemplateConfiguration.skipNoAssetsFound
            }

            # Use $($account.TopdeskAssets) in your notification configuration to resolve the queried assets
            $account.TopdeskAssets = Get-TopdeskAssetsByPersonId @splatParamsTopdeskAssets

            # TopdeskAssets can only be empty if the action needs to be skiped [SkipNoAssetsFound = true]
            if ([string]::IsNullOrEmpty($account.TopdeskAssets)) {
                throw 'Action skip'
            }
        }
    }
    #endregion lookup global

    Write-Verbose "Scriptflow [$($actionContext.TemplateConfiguration.scriptFlow)]"

    #region look incident
    if ($actionContext.TemplateConfiguration.scriptFlow -eq 'Incident') {

        # Add value to request object
        $requestObject += @{
            callerLookup = @{
                id = $TopdeskPerson.id
            }
        }

        # Validate length of RequestShort, RequestShort will be shortened if the length is exceeded
        $splatParamsValidateRequestShort = @{
            Description   = Format-Description $actionContext.TemplateConfiguration.RequestShort
            AllowedLength = 80
            AttributeName = 'requestShort'
        }

        # Add value to request object
        $requestObject += @{
            briefDescription = Confirm-Description @splatParamsValidateRequestShort
        }

        # Add differences
        if ($actionContext.TemplateConfiguration.ShowDifferences -and $actionContext.Differences.Count -gt 0) {
            $description = ConvertDifferencesTo-Html -Description $actionContext.TemplateConfiguration.RequestDescription
        }
        else {
            $description = $actionContext.TemplateConfiguration.RequestDescription
        }

        $splatParamsRequest = @{
            Description = Format-Description $description
        }
    
        # Add value to request object
        $requestObject += @{
            request = Convert-To-HTML-Tag @splatParamsRequest
        }


        if (-not [string]::IsNullOrEmpty($actionContext.TemplateConfiguration.Action)) {
            $splatParamsAction = @{
                Description = Format-Description $actionContext.TemplateConfiguration.Action
            }
        
            # Add value to request object
            $requestObject += @{
                action = Convert-To-HTML-Tag @splatParamsAction
            }
        }
        # Add value to request opject firstLine or secondLine
        if (-not [string]::IsNullOrEmpty($actionContext.TemplateConfiguration.Status)) {
            $requestObject += @{
                status = $actionContext.TemplateConfiguration.Status
            }
        }

        # Resolve branch id
        if (-not [string]::IsNullOrEmpty($actionContext.TemplateConfiguration.Branch)) {
            $splatParamsBranch = @{
                BaseUrl         = $actionContext.Configuration.baseUrl
                Headers         = $authHeaders
                Class           = 'Branch'
                Value           = $actionContext.TemplateConfiguration.Branch
                Endpoint        = '/tas/api/branches'
                SearchAttribute = 'name'
            }

            # Add branch to request object
            $requestObject += @{
                branch = @{
                    id = Get-TopdeskIdentifier @splatParamsBranch
                }
            }
        }
        
        # Resolve operatorgroup id
        if (-not [string]::IsNullOrEmpty($actionContext.TemplateConfiguration.OperatorGroup)) {
            $splatParamsOperatorGroup = @{
                BaseUrl         = $actionContext.Configuration.baseUrl
                Headers         = $authHeaders
                Class           = 'OperatorGroup'
                Value           = $actionContext.TemplateConfiguration.OperatorGroup
                Endpoint        = '/tas/api/operatorgroups'
                SearchAttribute = 'groupName'
            }

            # Add operatorgroup to request object
            $requestObject += @{
                operatorGroup = @{
                    id = Get-TopdeskIdentifier @splatParamsOperatorGroup
                }
            }
        }

        # Resolve operator id 
        if (-not [string]::IsNullOrEmpty($actionContext.TemplateConfiguration.Operator)) {
            $splatParamsOperator = @{
                BaseUrl         = $actionContext.Configuration.baseUrl
                Headers         = $authHeaders
                Class           = 'Operator'
                Value           = $actionContext.TemplateConfiguration.Operator
                Endpoint        = '/tas/api/operators'
                SearchAttribute = $actionContext.TemplateConfiguration.OperatorCorrelation
            }
    
            #Add Impact to request object
            $requestObject += @{
                operator = @{
                    id = Get-TopdeskIdentifier @splatParamsOperator
                }
            }
        }

        # Resolve category id
        if (-not [string]::IsNullOrEmpty($actionContext.TemplateConfiguration.Category)) {    
            $splatParamsCategory = @{
                BaseUrl         = $actionContext.Configuration.baseUrl
                Headers         = $authHeaders
                Class           = 'Category'
                Value           = $actionContext.TemplateConfiguration.Category
                Endpoint        = '/tas/api/incidents/categories'
                SearchAttribute = 'name'
            }

            # Add category to request object
            $requestObject += @{
                category = @{
                    id = Get-TopdeskIdentifier @splatParamsCategory
                }
            }
        }

        # Resolve subCategory id
        if (-not [string]::IsNullOrEmpty($actionContext.TemplateConfiguration.SubCategory)) {   
            $splatParamsCategory = @{
                BaseUrl         = $actionContext.Configuration.baseUrl
                Headers         = $authHeaders
                Class           = 'SubCategory'
                Value           = $actionContext.TemplateConfiguration.SubCategory
                Endpoint        = '/tas/api/incidents/subcategories'
                SearchAttribute = 'name'
            }

            # Add subCategory to request object
            $requestObject += @{
                subcategory = @{
                    id = Get-TopdeskIdentifier @splatParamsCategory
                }
            }
        }

        # Resolve CallType id
        if (-not [string]::IsNullOrEmpty($actionContext.TemplateConfiguration.CallType)) {
            $splatParamsCallType = @{
                BaseUrl         = $actionContext.Configuration.baseUrl
                Headers         = $authHeaders
                Class           = 'CallType'
                Value           = $actionContext.TemplateConfiguration.CallType
                Endpoint        = '/tas/api/incidents/call_types'
                SearchAttribute = 'name'
            }

            # Add CallType to request object
            $requestObject += @{
                callType = @{
                    id = Get-TopdeskIdentifier @splatParamsCallType
                }
            }
        }

        # Resolve Impact id 
        if (-not [string]::IsNullOrEmpty($actionContext.TemplateConfiguration.Impact)) {
            $splatParamsImpact = @{
                BaseUrl         = $actionContext.Configuration.baseUrl
                Headers         = $authHeaders
                Class           = 'Impact'
                Value           = $actionContext.TemplateConfiguration.Impact
                Endpoint        = '/tas/api/incidents/impacts'
                SearchAttribute = 'name'
            }

            # Add Impact to request object
            $requestObject += @{
                impact = @{
                    id = Get-TopdeskIdentifier @splatParamsImpact
                }
            }
        }

        if (-not [string]::IsNullOrEmpty($actionContext.TemplateConfiguration.Priority)) {
            # Resolve priority id 
            $splatParamsPriority = @{
                BaseUrl         = $actionContext.Configuration.baseUrl
                Headers         = $authHeaders
                Class           = 'Priority'
                Value           = $actionContext.TemplateConfiguration.Priority
                Endpoint        = '/tas/api/incidents/priorities'
                SearchAttribute = 'name'
            }
        

            # Add Impact to request object
            $requestObject += @{
                priority = @{
                    id = Get-TopdeskIdentifier @splatParamsPriority
                }
            }
        }

        # Resolve entrytype id 
        if (-not [string]::IsNullOrEmpty($actionContext.TemplateConfiguration.EntryType)) {
            $splatParamsEntryType = @{
                BaseUrl         = $actionContext.Configuration.baseUrl
                Headers         = $authHeaders
                Class           = 'EntryType'
                Value           = $actionContext.TemplateConfiguration.EntryType
                Endpoint        = '/tas/api/incidents/entry_types'
                SearchAttribute = 'name'
            }
        
            # Add Impact to request object
            $requestObject += @{
                entryType = @{
                    id = Get-TopdeskIdentifier @splatParamsEntryType
                }
            }
        }

        # Resolve urgency id 
        if (-not [string]::IsNullOrEmpty($actionContext.TemplateConfiguration.Urgency)) {
            $splatParamsUrgency = @{
                BaseUrl         = $actionContext.Configuration.baseUrl
                Headers         = $authHeaders
                Class           = 'Urgency'
                Value           = $actionContext.TemplateConfiguration.Urgency
                Endpoint        = '/tas/api/incidents/urgencies'
                SearchAttribute = 'name'
            }
        
            # Add Impact to request object
            $requestObject += @{
                urgency = @{
                    id = Get-TopdeskIdentifier @splatParamsUrgency
                }
            }
        }

        # Resolve ProcessingStatus id 
        if (-not [string]::IsNullOrEmpty($actionContext.TemplateConfiguration.ProcessingStatus)) {
            $splatParamsProcessingStatus = @{
                BaseUrl         = $actionContext.Configuration.baseUrl
                Headers         = $authHeaders
                Class           = 'ProcessingStatus'
                Value           = $actionContext.TemplateConfiguration.ProcessingStatus
                Endpoint        = '/tas/api/incidents/statuses'
                SearchAttribute = 'name'
            }
        
            # Add Impact to request object
            $requestObject += @{
                processingStatus = @{
                    id = Get-TopdeskIdentifier @splatParamsProcessingStatus
                }
            }
        }

        if ($outputContext.AuditLogs.isError -contains $true) {
            Throw "Error(s) occured while looking up required values"
        }
    }
    #endregion look incident

    #region look change
    elseif ($actionContext.TemplateConfiguration.scriptFlow -eq 'Change') {
        
        # Add Topdeskperson id to request object
        $requestObject += @{
            requester = @{
                id = $TopdeskPerson.id
            }
        }
        #region lookuptemplate
        # Lookup Topdesk template id
        $splatParamsTopdeskTemplate = @{
            Headers = $authHeaders
            BaseUrl = $actionContext.Configuration.baseUrl
            Id      = $actionContext.TemplateConfiguration.Template
        }
    
        $requestObject += @{
            template = @{
                id = Get-TopdeskTemplateById @splatParamsTopdeskTemplate
            }
        }
    
        #Validate length of briefDescription, briefDescription will be shortened if the length is exceeded
        $splatParamsValidateBriefDescription = @{
            Description   = Format-Description $actionContext.TemplateConfiguration.BriefDescription
            AllowedLength = 80
            AttributeName = 'BriefDescription'
        }
    
        # Add value to request object
        $requestObject += @{
            briefDescription = Confirm-Description @splatParamsValidateBriefDescription
        }

        # Add differences
        if ($actionContext.TemplateConfiguration.ShowDifferences -and $actionContext.Differences.Count -gt 0) {
            $description = ConvertDifferencesTo-Text -Description $actionContext.TemplateConfiguration.Request
        }
        else {
            $description = $actionContext.TemplateConfiguration.Request
        }

        # Add value to request object
        $requestObject += @{
            request = Format-Description $description
        }
    
        # Validate change type
        $splatParamsTopdeskTemplate = @{
            changeType = $actionContext.TemplateConfiguration.ChangeType
        }
        $changeType = Get-TopdeskChangeType @splatParamsTopdeskTemplate
    
        # Add value to request object
        $requestObject += @{
            changeType = $changeType
        }
    
        # Support for optional parameters, are only added when they are not empty
        # Action
        if (-not [string]::IsNullOrEmpty($actionContext.TemplateConfiguration.Action)) {
            $requestObject += @{
                action = $actionContext.TemplateConfiguration.Action
            }
        }
    
        # Category
        if (-not [string]::IsNullOrEmpty($actionContext.TemplateConfiguration.Category)) {
            $requestObject += @{
                category = $actionContext.TemplateConfiguration.Category
            }
        }
    
        # SubCategory
        if (-not [string]::IsNullOrEmpty($actionContext.TemplateConfiguration.SubCategory)) {
            $requestObject += @{
                subCategory = $actionContext.TemplateConfiguration.SubCategory
            }
        }
    
        # ExternalNumber
        if (-not [string]::IsNullOrEmpty($actionContext.TemplateConfiguration.ExternalNumber)) {
            $requestObject += @{
                externalNumber = $actionContext.TemplateConfiguration.ExternalNumber
            }
        }
    
        # Impact
        if (-not [string]::IsNullOrEmpty($actionContext.TemplateConfiguration.Impact)) {
            $requestObject += @{
                impact = $actionContext.TemplateConfiguration.Impact
            }
        }
    
        # Benefit
        if (-not [string]::IsNullOrEmpty($actionContext.TemplateConfiguration.Benefit)) {
            $requestObject += @{
                benefit = $actionContext.TemplateConfiguration.Benefit
            }
        }
    
        # Priority
        if (-not [string]::IsNullOrEmpty($actionContext.TemplateConfiguration.Priority)) {
            $requestObject += @{
                priority = $actionContext.TemplateConfiguration.Priority
            }
        }
        
        if ($outputContext.AuditLogs.isError -contains $true) {
            Throw "Error(s) occured while looking up required values"
        }
    
        #endregion lookuptemplate
    }
    #endregion look change
    
    # Throw when scripFlow has a incorrect value
    else {
        Throw "Incorrect scriptFlow"
    }

    #region write
    if (-Not($actionContext.DryRun -eq $true)) {
        Write-Verbose "Sending notification for: [$($personContext.Person.DisplayName)]"

        if ($TopdeskPerson.status -eq 'personArchived') {
            Write-Verbose "Topdeskperson [$($TopdeskPerson.id)] will be unarchived"
            $shouldArchive = $true
            $splatParamsPersonUnarchive = @{
                TopdeskPerson   = [ref]$TopdeskPerson
                Headers         = $authHeaders
                BaseUrl         = $actionContext.Configuration.baseUrl
                Archive         = $false
                ArchivingReason = $actionContext.Configuration.personArchivingReason
            }
            Set-TopdeskPersonArchiveStatus @splatParamsPersonUnarchive
        }

        if ($actionContext.TemplateConfiguration.scriptFlow -eq 'Incident') {
            # Create incident in Topdesk
            $splatParamsTopdeskIncident = @{
                Headers         = $authHeaders
                baseUrl         = $actionContext.Configuration.baseUrl
                TopdeskIncident = $requestObject
            }
            $TopdeskResponse = New-TopdeskIncident @splatParamsTopdeskIncident
        }
        elseif ($actionContext.TemplateConfiguration.scriptFlow -eq 'Change') {
            # Create change in Topdesk
            $splatParamsTopdeskChange = @{
                Headers       = $authHeaders
                baseUrl       = $actionContext.Configuration.baseUrl
                TopdeskChange = $requestObject
            }
            $TopdeskResponse = New-TopdeskChange @splatParamsTopdeskChange
        }

        if ($shouldArchive -and $TopdeskPerson.status -ne 'personArchived') {
            Write-Verbose "Topdeskperson $($TopdeskPerson.id) will be archived"
            $splatParamsPersonArchive = @{
                TopdeskPerson   = [ref]$TopdeskPerson
                Headers         = $authHeaders
                BaseUrl         = $actionContext.Configuration.baseUrl
                Archive         = $true
                ArchivingReason = $actionContext.Configuration.personArchivingReason
            }
            Set-TopdeskPersonArchiveStatus @splatParamsPersonArchive
        }
        
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Message = "Sending notification [$($actionContext.TemplateConfiguration.scriptFlow)] for [$($personContext.Person.DisplayName)] with number [$($TopdeskResponse.number)] was successful."
                IsError = $false
            })
    }
    else {
        # Add an auditMessage showing what will happen during enforcement
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Message = "Sending notification [$($actionContext.TemplateConfiguration.scriptFlow)] for: [$($personContext.Person.DisplayName)], will be executed during enforcement"
            })
        Write-Verbose ($requestObject | ConvertTo-Json)
    }
    #endregion write
}
    
catch {
    $ex = $PSItem
    
    switch ($ex.Exception.Message) {

        'Incorrect scriptFlow' {
            $errorMessage = "Incorrect scriptFlow [$($actionContext.TemplateConfiguration.scriptFlow)]"
        }

        'Error(s) occured while looking up required values' {
            # Only log when there are no lookup values, as these generate their own audit message
        }

        'Action skip' {
            # If empty and [SkipNoAssetsFound = true] in the JSON, nothing should be done. Mark them as a success
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = 'Not creating TOPdesk notification, because no assets are found and [Skip when no asset is found] checkbox is enabled'
                    IsError = $false
                })
        }
        
        default {
            Write-Verbose ($ex | ConvertTo-Json) # Debug - Test
            if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
                $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
                $errorMessage = "Could not send TOPdesk notification [$($actionContext.TemplateConfiguration.scriptFlow)] for: [$($personContext.Person.DisplayName)]. Error: $($ex.ErrorDetails.Message)"
            }
            else {
                $errorMessage = "Could not send TOPdesk notification [$($actionContext.TemplateConfiguration.scriptFlow)] for: [$($personContext.Person.DisplayName)]. Error: $($ex.Exception.Message) $($ex.ScriptStackTrace)"
            } 
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = $errorMessage
                    IsError = $true
                })
        }
    }
    # End
}
finally {
    # Check if auditLogs contains errors, if no errors are found, set success to true
    if (-NOT($outputContext.AuditLogs.isError -contains $true)) {
        $outputContext.Success = $true
    }
}
