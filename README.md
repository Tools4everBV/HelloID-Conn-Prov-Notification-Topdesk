# HelloID-Conn-Prov-Notification-Topdesk

| :warning: Warning                                                                                                                                                                                                                                 |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Please be aware that the current notifications only can be triggered by built-in events. For other applications please use the Target connector [HelloID Topdesk target system](https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-Topdesk) |


| :information_source: Information                                                                                                                                                                                                                                                                                                                                                       |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements. |
<br />
<p align="center"> 
  <img src="https://www.tools4ever.nl/connector-logos/topdesk-logo.png">
</p>

## Table of contents

- [HelloID-Conn-Prov-Notification-Topdesk](#helloid-conn-prov-notification-topdesk)
  - [Table of contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Getting started](#getting-started)
    - [Prerequisites](#prerequisites)
    - [Connection settings](#connection-settings)
    - [Permissions](#permissions)
    - [Templates](#templates)
      - [Changes](#changes)
    - [Incidents](#incidents)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Introduction

_HelloID-Conn-Prov-Notification-Topdesk_ is a _notifcation_ connector. Topdesk provides a set of REST APIs that allow you to programmatically interact with its data. The [Topdesk API documentation](https://developers.topdesk.com/explorer/?page=supporting-files#/) provides details of API commands that are used.

## Getting started
### Prerequisites

  - Archiving reason that is configured in Topdesk
  - Credentials with the rights as described in permissions

### Connection settings

The following settings are required to connect to the API.

| Setting              | Description                                               | Mandatory |
| -------------------- | --------------------------------------------------------- | --------- |
| BaseUrl              | The URL to the API                                        | Yes       |
| UserName             | The UserName to connect to the API                        | Yes       |
| Password             | The Password to connect to the API                        | Yes       |
| Archiving reason     | Fill in an archiving reason that is configured in Topdesk | Yes       |
| Toggle debug logging | Creates extra logging for debug purposes                  | Yes       |

### Permissions

The following permissions are required to use this connector. This should be configured on a specific Permission Group for the Operator HelloID uses.

| Permission                    | Read | Write | Create | Archive |
| ----------------------------- | ---- | ----- | ------ | ------- |
| <b>Call Management</b>        |
| First line calls              | x    | x     | x      |         |
| Second line calls             | x    | x     | x      |         |
| Escalate calls                |      | x     |        |         |
| Link object to call           |      | x     |        |         |
| Link room to call             |      | x     |        |         |
| <b>Change Management</b>      |
| Requests for Simple Change    | x    | x     | x      |         |
| Requests for Extensive Change | x    | x     | x      |         |
| Simple Changes                | x    | x     |        |         |
| Extensive Changes             | x    | x     |        |         |
| <b>Supporting Files</b>       |
| Persons                       | x    | x     |        | x       |
| Operators                     | x    |       |        |         |
| Operator groups               | x    |       |        |         |
| Suppliers                     | x    |       |        |         |
| Rooms                         | x    |       |        |         |
| Supporting Files Settings     | x    | x     |        |         |
| <b>Reporting API</b>          |
| REST API                      | x    |       |        |         |
| Use application passwords     |      | x     |        |         |

### Templates

There are two different templates. One for changes and one for incidents. They can be mixed when configured in Topdesk.
| :warning: Warning                                                                                                                           |
| :------------------------------------------------------------------------------------------------------------------------------------------ |
|                                                                                                                                             |
| Please keep in mind that the key form field names in the templates are used in the notification.ps1 changing them will break the connector. |

It is possible to hide or disable (make them read-only) certain form fields if they are not used or should not be changed. For example, the branch should always be 'Baarn' and the field must be hidden in the configuration:

```JSON
  {
    "key": "Branch",
    "type": "input",
    "defaultValue": "Baarn",
    "templateOptions": {
      "label": "Branch",
      "description": "Fill in the branch name that is used in Topdesk. This is a mandatory lookup field.",
      "required": true,
    "disabled": true
    },
  "hide": true
  },
```

#### Changes
To create a form for changes the following template should be used: [template_change.json](https://github.com/Tools4everBV/HelloID-Conn-Prov-Notification-Topdesk/blob/main/template_change.json).

The table below describes the different form fields from the template.

| template key             | Description                                                                      | Mandatory |
| ------------------------ | -------------------------------------------------------------------------------- | --------- |
| scriptFlow               | Fixed value of Change (read-only)                                                | Yes       |
| TopdeskPersonCorrelation | Which Topdesk field is used to correlate the requester (employeeNumber or email) | Yes       |
| TopdeskPerson            | Fixed value or a HelloID variable of the requester                               | Yes       |
| Template                 | The code of the template from Topdesk                                            | Yes       |
| ChangeType               | Type of the change in Topdesk Simple or Extensive                                | Yes       |
| BriefDescription         | Title of the Topdesk Change                                                      | Yes       |
| Request                  | Request info that is shown in the Topdesk Change                                 | Yes       |
| Action                   | Optionally add an action to the Topdesk change                                   |           |
| Category                 | The category is commonly filled in the Topdesk change template                   |           |
| SubCategory              | The subcategory is commonly filled in the Topdesk change template                |           |
| Impact                   | The impact is filled in the Topdesk change template                              |           |
| Benefit                  | The benefit is commonly filled in the Topdesk change template                    |           |
| Priority                 | The priority is commonly filled in the Topdesk change template                   |           |

### Incidents
To create a form for incidents the following template should be used: [template_incident.json](https://github.com/Tools4everBV/HelloID-Conn-Prov-Notification-Topdesk/blob/main/template_incident.json).


| :information_source: Information                                                                                                                                                                                                                                                                                                                                                                                                       |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| The Topdesk incident API uses HTML tags. For example by using the tags <'strong'><'/strong'>. By default, we convert all "enter" (\n) to <'br'>, so you can just use the 'enter' button when filling in the Request Description and Action of the incident. For more information about the HTML tags: [Topdesk incident API documentation](https://developers.topdesk.com/documentation/index-apidoc.html#api-Incident-CreateIncident) |


The table below describes the different form fields from the template.

| Key                      | Description                                                                     | Mandatory |
| ------------------------ | ------------------------------------------------------------------------------- | --------- |
| scriptFlow               | Fixed value of Incident                                                         | Yes       |
| TopdeskPersonCorrelation | Which Topdesk field is used to correlate the caller (employeeNumber or email)   | Yes       |
| TopdeskPerson            | Fixed value or a HelloID variable of the caller                                 | Yes       |
| RequestShort             | Title of the Topdesk Incident                                                   | Yes       |
| RequestDescription       | Request info that is shown in the Topdesk Incident. HTML tags supported         | Yes       |
| Action                   | Optionally add an action to the Topdesk. HTML tags supported                    |           |
| Branch                   | Fill in a existing branch                                                       | Yes       |
| OperatorGroup            | Operator group name that will be assigned to the incident                       |           |
| OperatorCorrelation      | Which Topdesk field is used to correlate the operator (employeeNumber or email) |           |
| Operator                 | Operator that will be assigned to the incident                                  |           |
| Category                 | Fill in the category name that is used in Topdesk                               |           |
| SubCategory              | Fill in the subcategory name that is used in Topdesk                            |           |
| CallType                 | Fill in the branch call type that is used in Topdesk                            |           |
| Impact                   | Fill in the impact name that is used in Topdesk                                 |           |
| Priority                 | Fill in the priority name that is used in Topdesk                               |           |
| EntryType                | Fill in the entry type name that is used in Topdesk                             |           |
| Urgency                  | Fill in the urgency name that is used in Topdesk                                |           |
| ProcessingStatus         | Fill in the processing status name that is used in Topdesk                      |           |

| :information_source: Information                                                                                                         |
| :--------------------------------------------------------------------------------------------------------------------------------------- |
| Some fields in Topdesk are marked mandatory in the Topdesk configuration. These fields are default not marked mandatory in the template. |

## Getting help

> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/hc/en-us/articles/360012558020-Configure-a-custom-PowerShell-target-system) pages_

> _If you need help, feel free to ask questions on our [TODOwhenchangingtopublicforumPost](https://forum.helloid.com/forum/helloid-connectors/provisioning/1266-helloid-conn-prov-target-topdesk)_

## HelloID docs

> The official HelloID documentation can be found at: https://docs.helloid.com/