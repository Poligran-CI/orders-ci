// Pipeline de integración continua de orders-ci.
// Obtiene el código, ejecuta las pruebas, construye las imágenes, levanta los dos contenedores
// (API + PostgreSQL), ejecuta la operación de ejemplo (falla si el resultado no es el esperado)
// y retira los contenedores, también cuando la construcción falla.
// El disparo automático (Poll SCM) se define en jenkins/jenkins.yaml.

// Etapa en curso, para indicar dónde falló la construcción.
def currentStage = 'ninguna'

// docker compose con las credenciales de la base de datos tomadas de la credencial
// "orders-db" de Jenkins (variables DB_CREDS_USR y DB_CREDS_PSW). La primera línea desactiva
// la traza del shell (sh -x) para que ni el usuario ni la contraseña aparezcan en la consola.
def compose(String args) {
    sh '#!/bin/sh -e\necho "+ docker compose ' + args + '"\n' +
       'DB_USER="$DB_CREDS_USR" DB_PASSWORD="$DB_CREDS_PSW" docker compose ' + args
}

pipeline {
    agent any

    tools {
        jdk 'JDK21'
        maven 'Maven3'
    }

    options {
        timestamps()
        disableConcurrentBuilds()
        skipDefaultCheckout()
        timeout(time: 20, unit: 'MINUTES')
    }

    environment {
        // Proyecto, red, volumen y etiquetas propios de cada construcción.
        COMPOSE_PROJECT_NAME = "orders-ci-${env.BUILD_NUMBER}"
        COMPOSE_FILE = 'docker-compose.yml:docker-compose.ci.yml'
        IMAGE_TAG = "${env.BUILD_NUMBER}"
        DB_CREDS = credentials('orders-db')
        EXPECTED_TOTAL = '144000.00'
    }

    stages {
        stage('Obtener código') {
            steps {
                script { currentStage = env.STAGE_NAME }
                checkout scm
                sh 'git log -1 --format="Commit %h: %s (%an)"'
            }
        }

        stage('Pruebas unitarias') {
            steps {
                script { currentStage = env.STAGE_NAME }
                sh 'mvn -B test'
            }
            post {
                always {
                    junit allowEmptyResults: true, testResults: '**/target/surefire-reports/*.xml'
                }
            }
        }

        stage('Construir imagen') {
            steps {
                script { currentStage = env.STAGE_NAME }
                compose('build')
                sh 'docker image ls --filter "reference=orders-*:${IMAGE_TAG}"'
            }
        }

        stage('Levantar contenedores') {
            steps {
                script { currentStage = env.STAGE_NAME }
                // --wait espera a que db y api estén "healthy" (healthchecks de Compose y del Dockerfile).
                compose('up -d --wait --wait-timeout 180')
                compose('ps')
            }
        }

        stage('Operación de ejemplo') {
            steps {
                script { currentStage = env.STAGE_NAME }
                sh 'sh scripts/verificar_operacion.sh "${COMPOSE_PROJECT_NAME}_default" "${EXPECTED_TOTAL}"'
            }
        }
    }

    post {
        success {
            echo 'Construcción exitosa: la operación de ejemplo devolvió el resultado esperado.'
        }
        failure {
            echo "La construcción falló en la etapa: ${currentStage}"
            // Registros de los contenedores para diagnosticar la falla (si llegaron a crearse).
            script {
                try {
                    compose('logs --no-color --tail=80')
                } catch (err) {
                    echo 'No hay contenedores de los que mostrar registros.'
                }
            }
        }
        cleanup {
            // Se ejecuta siempre, al final: retira contenedores, red, volumen e imágenes de esta construcción.
            script {
                try {
                    compose('down --volumes --remove-orphans --rmi all')
                } catch (err) {
                    echo "No se pudieron retirar los contenedores: ${err}"
                }
            }
        }
    }
}
