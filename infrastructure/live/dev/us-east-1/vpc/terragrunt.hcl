include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

include "component" {
  path           = "${dirname(find_in_parent_folders("root.hcl"))}/_common/vpc.hcl"
  merge_strategy = "deep"
}

inputs = {
  name = "${include.root.locals.cluster_name}-vpc"
}
