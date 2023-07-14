#####################################################
# HelloID-Conn-Prov-Notification-Topdesk-Incident
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
    if (-not($Template.PSobject.Properties.Name -Contains $Class)) {
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

#endregion functions

try {
    #region lookuptemplate
    # Setup authentication headers
    $authHeaders = Set-AuthorizationHeaders -UserName $Config.username -ApiKey $Config.apiKey

    # Resolve caller
    $splatParamsTopdeskCaller = @{
        Requester            = $template.Caller
        CorrelationAttribute = $template.CallerCorrelation
        Headers              = $authHeaders
        BaseUrl              = $config.baseUrl
    }

    $TopdeskPerson = Get-TopdeskPersonByCorrelationAttribute @splatParamsTopdeskCaller

    # Add value to request object
    $requestObject += @{
        callerLookup = @{
            id = $TopdeskPerson.id
        }
    }

    # Validate length of RequestShort
    $splatParamsValidateRequestShort = @{
        Description   = $template.RequestShort
        AllowedLength = 80
        AttributeName = 'requestShort'
    }

    Confirm-Description @splatParamsValidateRequestShort
    
    # Add value to request object
    $requestObject += @{
        briefDescription = $template.RequestShort
    }

    
    $splatParamsRequest = @{
        Description = $template.RequestDescription1 + $template.RequestDescription2 + $template.RequestDescription3 + $template.RequestDescription4 + $template.RequestDescription5
    }
    
    # Add value to request object
    $requestObject += @{
        request = Convert-To-HTML-Tag @splatParamsRequest
    }


    if (-not [string]::IsNullOrEmpty($template.Action)) {
        $splatParamsAction = @{
            Description = $template.Action
        }
        
        # Add value to request object
        $requestObject += @{
            action = Convert-To-HTML-Tag @splatParamsAction
        }
    }

    # Resolve branch id
    $splatParamsBranch = @{
        BaseUrl         = $config.baseUrl
        Headers         = $authHeaders
        Class           = 'Branch'
        Value           = $template.Branch
        Endpoint        = '/tas/api/branches'
        SearchAttribute = 'name'
    }

    # Add branch to request object
    $requestObject += @{
        branch = @{
            id = Get-TopdeskIdentifier @splatParamsBranch
        }
    }
    
    # Resolve operatorgroup id
    if (-not [string]::IsNullOrEmpty($template.OperatorGroup)) {
        $splatParamsOperatorGroup = @{
            BaseUrl         = $config.baseUrl
            Headers         = $authHeaders
            Class           = 'OperatorGroup'
            Value           = $template.OperatorGroup
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
    if (-not [string]::IsNullOrEmpty($template.Operator)) {
        $splatParamsOperator = @{
            BaseUrl         = $config.baseUrl
            Headers         = $authHeaders
            Class           = 'Operator'
            Value           = $template.Operator
            Endpoint        = '/tas/api/operators'
            SearchAttribute = $template.OperatorCorrelation
        }
    
        #Add Impact to request object
        $requestObject += @{
            operator = @{
                id = Get-TopdeskIdentifier @splatParamsOperator
            }
        }
    }

    # Resolve category id
    if (-not [string]::IsNullOrEmpty($template.Category)) {    
        $splatParamsCategory = @{
            BaseUrl         = $config.baseUrl
            Headers         = $authHeaders
            Class           = 'Category'
            Value           = $template.Category
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
    if (-not [string]::IsNullOrEmpty($template.SubCategory)) {   
        $splatParamsCategory = @{
            BaseUrl         = $config.baseUrl
            Headers         = $authHeaders
            Class           = 'SubCategory'
            Value           = $template.SubCategory
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
    if (-not [string]::IsNullOrEmpty($template.CallType)) {
        $splatParamsCategory = @{
            BaseUrl         = $config.baseUrl
            Headers         = $authHeaders
            Class           = 'CallType'
            Value           = $template.CallType
            Endpoint        = '/tas/api/incidents/call_types'
            SearchAttribute = 'name'
        }

        # Add CallType to request object
        $requestObject += @{
            callType = @{
                id = Get-TopdeskIdentifier @splatParamsCategory
            }
        }
    }

    # Resolve Impact id 
    if (-not [string]::IsNullOrEmpty($template.Impact)) {
        $splatParamsCategory = @{
            BaseUrl         = $config.baseUrl
            Headers         = $authHeaders
            Class           = 'Impact'
            Value           = $template.Impact
            Endpoint        = '/tas/api/incidents/impacts'
            SearchAttribute = 'name'
        }

        # Add Impact to request object
        $requestObject += @{
            impact = @{
                id = Get-TopdeskIdentifier @splatParamsCategory
            }
        }
    }

    if (-not [string]::IsNullOrEmpty($template.Priority)) {
        # Resolve priority id 
        $splatParamsPriority = @{
            BaseUrl         = $config.baseUrl
            Headers         = $authHeaders
            Class           = 'Priority'
            Value           = $template.Priority
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
    if (-not [string]::IsNullOrEmpty($template.EntryType)) {
        $splatParamsEntryType = @{
            BaseUrl         = $config.baseUrl
            Headers         = $authHeaders
            Class           = 'EntryType'
            Value           = $template.EntryType
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
    if (-not [string]::IsNullOrEmpty($template.Urgency)) {
        $splatParamsUrgency = @{
            BaseUrl         = $config.baseUrl
            Headers         = $authHeaders
            Class           = 'Urgency'
            Value           = $template.Urgency
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
    if (-not [string]::IsNullOrEmpty($template.ProcessingStatus)) {
        $splatParamsProcessingStatus = @{
            BaseUrl         = $config.baseUrl
            Headers         = $authHeaders
            Class           = 'ProcessingStatus'
            Value           = $template.ProcessingStatus
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

    #endregion lookuptemplate

    if (-Not($actionContext.DryRun -eq $true)) {
        Write-Verbose "Sending notification for: [$($personContext.Person.DisplayName)]"

        if ($TopdeskPerson.status -eq 'personArchived') {
            Write-Verbose "Caller [$($TopdeskPerson.id)] will be unarchived"
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
        $splatParamsTopdeskIncident = @{
            Headers         = $authHeaders
            baseUrl         = $config.baseUrl
            TopdeskIncident = $requestObject
        }
        $TopdeskChange = New-TopdeskIncident @splatParamsTopdeskIncident

        if ($shouldArchive -and $TopdeskPerson.status -ne 'personArchived') {
            Write-Verbose "Caller $($TopdeskPerson.id) will be archived"
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