[
    {
      "name": "${name}",
      "image": "${container_image}",
      "cpu": ${cpu},
      "memory": ${memory},
      "memoryReservation": ${memory},
      "environment": [
        { "name" : "JAVA_OPTS", "value" : "-Djenkins.install.runSetupWizard=false" }
      ],
      "essential": true,
      "mountPoints": [
        {
          "containerPath": "${jenkins_home}",
          "sourceVolume": "${source_volume}"
        }
      ],
      "portMappings": [
        {
          "containerPort": ${jenkins_controller_port}
        },
        {
          "containerPort": ${jnlp_port}
        }
      ]
    }
]
