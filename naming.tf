# Centralized naming convention for SIE GCP resources.
# Single source of truth for resource name suffixes, consumed via
# local.name_suffixes in infra/main.tf.

locals {
  name_suffixes = {
    cluster     = ""
    network     = "-network"
    subnet      = "-subnet"
    router      = "-router"
    nat         = "-nat"
    nodes_sa    = "-nodes"
    workload_sa = "-workload"
    registry    = "-images"
  }
}
