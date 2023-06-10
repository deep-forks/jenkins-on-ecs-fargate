[
    {
      "name": "${name}",
      "image": "${container_image}",
      "cpu": ${cpu},
      "memory": ${memory},
      "memoryReservation": ${memory},

      "essential": true,
      "portMappings": [
        {
          "containerPort": ${sonarqube_controller_port}
        }
      ],
      "environment":
        [
            {
                "name": "SONAR_JDBC_URL",
                "value": "${sonar_jdbc_url}"
            },
            {
                "name": "SONAR_JDBC_USERNAME",
                "value": "${sonar_jdbc_username}"
            },
            {
                "name": "SONAR_ES_BOOTSTRAP_CHECKS_DISABLE",
                "value": "true"
            }
        ],
        "mountPoints": [],
        "volumesFrom": [],
        "secrets": [
            {
                "name": "SONAR_JDBC_PASSWORD",
                "valueFrom": "${sonar_jdbc_password_secret_arn}"
            }
        ],
        "logConfiguration": {
            "logDriver": "awslogs",
            "options": {
                "awslogs-create-group": "true",
                "awslogs-group": "${log_group}",
                "awslogs-region": "${region}",
                "awslogs-stream-prefix": "${name}-stream"
            }
        }
    }
]
