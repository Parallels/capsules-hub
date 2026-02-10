# Changelog - Application Hub

All notable changes to the Application Hub module will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.0.28] - 2026-02-10



## [0.0.27] - 2026-02-05

- Fixed an issue where we were not able to disable https and use of the secure app
- Fixed an issue in one of the endpoints where a lxc service would fail to update
- Added the new ui-library module so we can share the UI between the capsule-marketplace, capsules-hub and others in the future
- Moved the capsule-marketplace to use the new ui-lib

## [0.0.26] - 2026-01-29

## [0.0.25] - 2026-01-29

- added a recovery method to allow users to recover the licenses from the capsules-hub - fixes #146

## [0.0.24] - 2026-01-28

- Added a channel selection to the settings to decide the update channel
- Added a dynamic updater mechanism, fixes #142
- Removed the checkbox in the end of the technical feedback, fixes #138
- Fixed an issue with the notification polling using the wrong url
- Fixed an error on the app-feedback using the wrong type
- fixed an error where the technical report woul not use the right endpoint
- Unified the error messages from the capsule-hub backend into a single file
- Removed the retry messages from the splashscreen but kept the logs #133
- Removed any raw errors from the UI but kept them in the logs #134
- Improved some of the messages to the user

## [0.0.22] - 2026-01-20

- Reworked DNS resolver
- Further improvements in the Marketplace
- Fixed a bug where you were not able to install a application that you had searched in the apps
- Further stabilisation of the system
- Added extra fields for the capsules blueprint

## [0.0.21] - 2026-01-19

- Improved some UI changes for the marketplace
- Added the new dns-resolver to the list of modules in attempt to fix dns issues
- Other fixes

## [0.0.20] - 2026-01-15

- Improved the way we deal with user feedback
- Added extra fields to the Capsules #118
- Added the new marketplace application #116
- Added a recovery for DNS issues with dnsmasq
- Added a new wait for the app to be ready
- Added better usage of urls when opening the page
- Added the new links to the marketplace

## [0.0.19] - 2025-12-19

## [0.0.18] - 2025-12-19

- Added a new flow for the user when they have a application that requires credentials, fix #106
- Fixed an issue where a modal error was showing in the wrong place #105
- Fixed some minor issues with the UI, fix #109
- rebranded the application hub to the new Capsule Hub, fixes #102
- Implement a notification modal system, triggered by backend network errors or anything else
- Added debug controls, with a centralized modal size definition.
- Added specialized message for specific no local network error fixes #96
- Added a retry process for the install script if it fails first time #93
- Added a `Report Issue` button in the splashscreen in case of errors to share info #97
- Fixed a bug where the initialization script was run a second time with no need #95
- Fixed some issues with initialization variables

## [0.0.17] - 2025-12-11

- Fixed an issue where Onboarding would failed for users that had used old capsules app
- Fixed an issue where the marketplace would crash if two users had an empty email
- Fixed issues with the users database constrains
- Updated install scripts to not overwrite the existing .env file
- refactor of the UI components
- some fixes for the backend

## [0.0.16] - 2025-12-09

## [0.0.15] - 2025-12-03

- Defer the initialization until the onboarding is done
- Fixed an issue with the authService missing variables
- Added a recache of the auth tokens

## [0.0.14] - 2025-12-03

- Moved all controls to the new design system
- Added some debug controls
- Fixed some issues with the UX Controls

## [0.0.13] - 2025-10-30

- Introduced constants for various feedback colors.
- Created FeedbackFormData interface to structure feedback submissions.
- Defined FeedbackPayload and FeedbackPayloadField interfaces for detailed feedback data.
- Started refactoring on the UI for the new controls
- Added the new feedback modal
- Improved the Modal engine
- Lots of UI tweaks
- Removed unnecessary calls to configService.init() in various components.
- Updated config fetching logic to use DEFAULT_CONFIG as fallback.
- Simplified debug tab management in Home component.
- Enhanced memoization in ConfigService for improved performance.
- Added application ready listener in SSEService for better connection handling.
- Improved logging throughout the application for better traceability.
- Cleaned up unused code and comments in ConfigService.
- Adjusted AuthService to dynamically construct login URLs based on configuration.
- Removed tenant_id from LoginCredentials interface as it was not used.
- Move the internet check to a curl instead of a ping

## [0.0.12] - 2025-10-23

- Added more telemetry
- Improved the reset script
- Added the reset script to the application hub release

## [0.0.11] - 2025-10-23

- Improved the design of the error dialog
- Fixed an issue where the error messages from the backend API would generate an error
- Enabled the debug messages in the log of the backend
- Fixed an issue in the install script that had the wrong variable name for the marketplace
- Fixed an issue in the search bar where it was not detecting empty strings and resetting the view

## [0.0.10] - 2025-10-21

- Added a better LogService to send logs to the backend
- Removed some of the Debug Panels
- Improved logic in how the Debug Panels are showned
- Removed some of the debug buttons from the header

## [0.0.9] - 2025-10-20

- fixed an issue that would now allow the initial run to setup config values in the UI
- Fixed an issue with the StatusBar showing debug icons
- Removed some temporary files from the repo
- Modified release-capsule-marketplace-registry.yml to change environment descriptions and suffixes for canary and beta.
- Updated release-common-cleanup.yml to reflect new environment handling.
- Adjusted release-coordinator.yml to include canary and beta as options.
- Enhanced set-build-env.sh to propagate IS_CANARY and IS_BETA environment variables.
- Updated build.rs to embed IS_CANARY and IS_BETA into the build.
- Modified backend_manager.rs to handle service port dynamically and adjust health check URLs.
- Enhanced main.rs to set application configurations for canary and beta environments.
- Updated AppConfig interface to include isCanary and isBeta flags.
- Adjusted ConfigService to manage environment checks for canary and beta.
- Updated Makefiles for capsule-agent and capsule-agent-updater to include IS_BETA and IS_CANARY build flags.
- Enhanced telemetry to include environment and channel information.
- Added reset-application-hub.sh script for clearing user data and caches.
- Addressed a bug that could have stopped the way we started the app at first run
- Added a script to reset the application to the default to allow debugging

## [0.0.8] - 2025-10-17

## [0.0.7] - 2025-10-16

- Implemented model options for Ollama and OpenAI models in `models.ts`.
- Created string utility functions for boolean conversion, string normalization, and environment checks in `stringUtils.ts`.
- Developed toast utility for handling timestamps in `toastUtils.ts`.
- Added version management functions including version parsing and comparison in `version.ts`.
- Created VM utility functions for retrieving OS logos in `vmUtils.tsx`.
- Configured Tailwind CSS in `tailwind.config.js`.
- Added HTML test pages for Parallels Desktop functionality and secrets management.
- Set up TypeScript configuration files for the project in `tsconfig.json` and `tsconfig.node.json`.
- Configured Vite for the application build process in `vite.config.ts`.
- Enhance issue templates and workflows to extract changelog content for releases #38

## [0.0.0] - 2024-08-26

- Initial release of Application Hub
