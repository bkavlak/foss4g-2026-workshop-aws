output "namespace" {
  value = helm_release.workshop.namespace
}

output "access_command" {
  description = "Prints the URL to hand to participants once the load balancer is up."
  value = join(" ", [
    "kubectl -n ${helm_release.workshop.namespace} get svc proxy-public",
    "-o jsonpath='http://{.status.loadBalancer.ingress[0].hostname}'",
  ])
}
