FROM jenkins/jenkins:2.541.3-jdk17

ARG JENKINS_VERSION=2.541.3
ENV CASC_JENKINS_CONFIG=/var/jenkins_casc/jenkins.yaml \
    JAVA_OPTS=-Djenkins.install.runSetupWizard=false

# Build tools inside the image (no host-specific mounts needed).
# The paths match the tool homes declared in jenkins.yaml (JDK21 and Maven3).
COPY --from=eclipse-temurin:21-jdk /opt/java/openjdk /opt/jdk21
COPY --from=maven:3.9-eclipse-temurin-21 /usr/share/maven /usr/share/maven
COPY --from=docker:29-cli /usr/local/bin/docker /usr/bin/docker
# BuildKit (buildx) plugin: avoids the deprecated legacy builder in the "Docker Build" stage.
COPY --from=docker:29-cli /usr/local/libexec/docker/cli-plugins/docker-buildx /usr/libexec/docker/cli-plugins/docker-buildx

COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt --jenkins-version ${JENKINS_VERSION}

COPY jenkins.yaml /var/jenkins_casc/jenkins.yaml

USER jenkins
