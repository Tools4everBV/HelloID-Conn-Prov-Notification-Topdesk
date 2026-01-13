# Changelog

All notable changes to this project will be documented in this file.

## [1.4.1]

### Added
- Support for email-based correlation when retrieving assets
- New template configuration option `TopdeskPersonCorrelation` to specify correlation method (employeeNumber or email)

### Changed
- Refactored asset retrieval logic to support multiple correlation methods
- Asset lookup now uses a switch statement to handle different correlation attributes

### Fixed
- Asset retrieval now correctly handles cases where requester and person use different correlation attributes
- Fixed issue #11. When multiple subcategories are found the correct one is now selected.

### Removed
- Debug toggle, changed `write-verbose` to `write-information`

## [1.4.0] - 2024

### Added
- New feature add differences

## [1.3.1]

### Added
- Partner solution id in header

## [1.3.0]

### Changed
- Branch is now optional

## [1.2.2]

### Added
- Status for incidents firstline secondline

## [1.2.1]

### Changed
- Update notification.ps1

## [1.2.0]

### Changed
- Moved assets to template

## [1.1.0]

### Fixed
- One note hotfix

### Added
- Query assets feature
