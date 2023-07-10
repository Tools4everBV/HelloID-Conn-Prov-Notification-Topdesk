#####################################################
# HelloID-Conn-Prov-Notification-Topdesk-Change
#
# Version: 0.1.0
#####################################################

# Initialize default values
$config = $actionContext.Configuration
$template = $actionContext.TemplateConfiguration
$success = $false

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Set debug logging
switch ($($config.IsDebug)) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
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
    $authHeaders.Add("Accept", 'application/json')

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
        $errorMessage = "Could not send notification. The attribute [$AttributeName] exceeds the max amount of [$AllowedLength] characters. Please shorten the value for this attribute in the JSON file. Value: [$Description]"
        
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Message = $errorMessage
                IsError = $true
            })
    }
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
#endregion

try {

    #region lookuptemplate
    # Setup authentication headers
    $authHeaders = Set-AuthorizationHeaders -UserName $Config.username -ApiKey $Config.apiKey

    # Lookup Topdesk template id
    $splatParamsTopdeskTemplate = @{
        Headers = $authHeaders
        BaseUrl = $config.baseUrl
        Id      = $template.Template
    }
    $templateId = Get-TopdeskTemplateById @splatParamsTopdeskTemplate

    # Add value to  request object
    $requestObject += @{
        template = @{
            id = $templateId
        }
    }

    #Validate length of briefDescription
    $splatParamsValidateBriefDescription = @{
        Description   = $template.BriefDescription
        AllowedLength = 80
        AttributeName = 'BriefDescription'
    }
    Confirm-Description @splatParamsValidateBriefDescription

    # Add value to request object
    $requestObject += @{
        briefDescription = $briefDescription
    }

    # Add value to request object
    $requestObject += @{
        request = $template.Request1 + $template.Request2 + $template.Request3 + $template.Request4 + $template.Request5
    }

    # Resolve requester
    $splatParamsTopdeskRequester = @{
        Requester            = $template.Requester
        CorrelationAttribute = $template.RequesterCorrelation
        Headers              = $authHeaders
        BaseUrl              = $config.baseUrl
    }
    $TopdeskPerson = Get-TopdeskPersonByCorrelationAttribute @splatParamsTopdeskRequester

    # Add value to request object
    $requestObject += @{
        requester = @{
            id = $TopdeskPerson.id
        }
    }

    # Validate change type
    $splatParamsTopdeskTemplate = @{
        changeType = $template.ChangeType
    }
    $changeType = Get-TopdeskChangeType @splatParamsTopdeskTemplate

    # Add value to request object
    $requestObject += @{
        changeType = $changeType
    }

    ## Support for optional parameters, are only added when they are not empty
    # Action
    if (-not [string]::IsNullOrEmpty($template.Action)) {
        $requestObject += @{
            action = $template.Action
        }
    }

    # Category
    if (-not [string]::IsNullOrEmpty($template.Category)) {
        $requestObject += @{
            category = $template.Category
        }
    }

    # SubCategory
    if (-not [string]::IsNullOrEmpty($template.SubCategory)) {
        $requestObject += @{
            subCategory = $template.SubCategory
        }
    }

    # ExternalNumber
    if (-not [string]::IsNullOrEmpty($template.ExternalNumber)) {
        $requestObject += @{
            externalNumber = $template.ExternalNumber
        }
    }

    # Impact
    if (-not [string]::IsNullOrEmpty($template.Impact)) {
        $requestObject += @{
            impact = $template.Impact
        }
    }

    # Benefit
    if (-not [string]::IsNullOrEmpty($template.Benefit)) {
        $requestObject += @{
            benefit = $template.Benefit
        }
    }

    # Priority
    if (-not [string]::IsNullOrEmpty($template.Priority)) {
        $requestObject += @{
            priority = $template.Priority
        }
    }
    
    if ($outputContext.AuditLogs.isError -contains $true) {
        Throw "Error(s) occured while looking up required values"
    }

    if (-Not($actionContext.DryRun -eq $true)) {
        Write-Verbose "Sending notification for: [$($personContext.Person.DisplayName)]"

        if ($TopdeskPerson.status -eq 'personArchived') {
            Write-Verbose "Requester [$($TopdeskPerson.id)] will be unarchived"
            $shouldArchive = $true
            $splatParamsPersonUnarchive = @{
                TopdeskPerson   = [ref]$TopdeskPerson
                Headers         = $authHeaders
                BaseUrl         = $config.baseUrl
                Archive         = $false
                ArchivingReason = $config.personArchivingReason
            }
            Set-TopdeskPersonArchiveStatus @splatParamsPersonUnarchive
        }

        # Create change in Topdesk
        $splatParamsTopdeskChange = @{
            Headers       = $authHeaders
            baseUrl       = $config.baseUrl
            TopdeskChange = $requestObject
        }
        $TopdeskChange = New-TopdeskChange @splatParamsTopdeskChange

        if ($shouldArchive -and $TopdeskPerson.status -ne 'personArchived') {
            Write-Verbose "Requester $($TopdeskPerson.id) will be archived"
            $splatParamsPersonArchive = @{
                TopdeskPerson   = [ref]$TopdeskPerson
                Headers         = $authHeaders
                BaseUrl         = $config.baseUrl
                Archive         = $true
                ArchivingReason = $config.personArchivingReason
            }
            Set-TopdeskPersonArchiveStatus @splatParamsPersonArchive
        }
        
        $success = $true
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Message = "Sending notification for [$($personContext.Person.DisplayName)] with number [$($TopdeskChange.number)] was successful."
                IsError = $false
            })
    }
    else {
        # Add an auditMessage showing what will happen during enforcement
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Message = "Sending notification for: [$($personContext.Person.DisplayName)], will be executed during enforcement"
            })
        Write-Verbose ($requestObject | ConvertTo-Json)
    }
}
catch {
    $success = $false
    $ex = $PSItem
    
    switch ($ex.Exception.Message) {

        'HelloID Template not found' {
            # Only log when there are no lookup values, as these generate their own audit message, set success based on error state
            $success = -Not($outputContext.AuditLogs.isError -contains $true)
        }

        'Error(s) occured while looking up required values' {
            # Only log when there are no lookup values, as these generate their own audit message
        }
        
        default {
            Write-Verbose ($ex | ConvertTo-Json) # Debug - Test
            if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
                $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
                $errorMessage = "Could not send TOPdesk notification for: [$($personContext.Person.DisplayName)]. Error: $($ex.ErrorDetails.Message)"
            }
            else {
                $errorMessage = "Could not send TOPdesk notification for: [$($personContext.Person.DisplayName)]. Error: $($ex.Exception.Message) $($ex.ScriptStackTrace)"
            } 
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = $errorMessage
                    IsError = $true
                })
        }
    }
    # End
}

$outputContext.Success = $success