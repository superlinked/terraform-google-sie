# Changelog

## [1.0.0](https://github.com/superlinked/terraform-google-sie/compare/v0.7.3...v1.0.0) (2026-10-01)


### ⚠ BREAKING CHANGES

* a configuration with an empty authorized_networks no longer plans. Set authorized_networks (an in-place update that adds master_authorized_networks_config), set enable_private_endpoint = true (an in-place update; requires enable_private_nodes), or set allow_public_api_server = true to keep the previous behaviour with no plan change. Configurations that already set authorized_networks keep working; Google Cloud public IP access is now pinned to disabled.

### Bug Fixes

* pin GKE deployment examples to SIE 0.9.0 ([#6](https://github.com/superlinked/terraform-google-sie/issues/6)) ([86acc90](https://github.com/superlinked/terraform-google-sie/commit/86acc9005c28cbf267473e632e4a861a2f40e181))
* stop leaving the GKE control plane open to every address ([#5](https://github.com/superlinked/terraform-google-sie/issues/5)) ([d67581c](https://github.com/superlinked/terraform-google-sie/commit/d67581c30fb70264918cef6524d37e0148a5c4c0))

## [0.7.3](https://github.com/superlinked/terraform-google-sie/compare/v0.7.2...v0.7.3) (2026-09-28)


### Bug Fixes

* pin GKE deployment examples to SIE 0.8.2 ([#2](https://github.com/superlinked/terraform-google-sie/issues/2)) ([0c70c94](https://github.com/superlinked/terraform-google-sie/commit/0c70c9483fc5a335c7c853894bd31fca194d05cf))
* pin GKE deployment examples to SIE 0.8.3 ([#4](https://github.com/superlinked/terraform-google-sie/issues/4)) ([a2421cf](https://github.com/superlinked/terraform-google-sie/commit/a2421cf97add238e6e35bc845c9838a1a8780fdf))
