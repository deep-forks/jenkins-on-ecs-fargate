// Output everything
output "jenkins_fargate_efs" {
  value = module.serverless_jenkins
}

// Output everything
output "sonarqube_fargate_efs" {
  value = module.serverless_sonarqube
}
