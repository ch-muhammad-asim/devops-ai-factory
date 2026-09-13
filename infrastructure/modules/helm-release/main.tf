provider "helm" {
  kubernetes = {
    host = var.kubernetes_host

    cluster_ca_certificate = var.cluster_ca_certificate_data == "" ? null : base64decode(var.cluster_ca_certificate_data)
    client_certificate     = var.client_certificate_data == "" ? null : base64decode(var.client_certificate_data)
    client_key             = var.client_key_data == "" ? null : base64decode(var.client_key_data)
  }
}

resource "helm_release" "this" {
  name       = var.release_name
  namespace  = var.namespace
  repository = var.repository
  chart      = var.chart
  version    = var.chart_version

  create_namespace = var.create_namespace
  atomic           = true
  cleanup_on_fail  = true
  wait             = true
  wait_for_jobs    = true
  timeout          = var.timeout_seconds
  max_history      = 10

  values = trimspace(var.values_yaml) == "" ? [] : [var.values_yaml]
}
