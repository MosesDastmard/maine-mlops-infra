# Jenkins Pipeline Templates

## Pipeline for: weekly-sales-store

Put this `Jenkinsfile` in your GitHub repo at the service path (e.g., `services/api/weekly-sales-store/Jenkinsfile`):

```groovy
pipeline {
    agent {
        kubernetes {
            yaml '''
apiVersion: v1
kind: Pod
spec:
  serviceAccountName: jenkins
  containers:
  - name: kaniko
    image: gcr.io/kaniko-project/executor:debug
    command: ["/busybox/sleep"]
    args: ["infinity"]
    volumeMounts:
    - name: docker-config
      mountPath: /kaniko/.docker
  - name: kubectl
    image: bitnami/kubectl:latest
    command: ["sleep"]
    args: ["infinity"]
  volumes:
  - name: docker-config
    secret:
      secretName: docker-registry-credentials
      items:
      - key: .dockerconfigjson
        path: config.json
'''
        }
    }
    
    environment {
        DOCKER_IMAGE = 'dastmard/maine-serve-weekly-sales-store'
        DEPLOY_NAMESPACE = 'services-api'
        DEPLOY_NAME = 'weekly-sales-store'
        SERVICE_PATH = 'services/api/weekly-sales-store'  // Path in your repo
    }
    
    triggers {
        // Generic Webhook Trigger - configure in GitHub
        GenericTrigger(
            genericVariables: [
                [key: 'ref', value: '$.ref'],
                [key: 'modified', value: '$.commits[*].modified[*]'],
                [key: 'added', value: '$.commits[*].added[*]']
            ],
            causeString: 'Triggered by GitHub push',
            token: 'weekly-sales-store-token',  // Webhook token
            regexpFilterText: '$ref $modified $added',
            regexpFilterExpression: 'refs/heads/main.*' + env.SERVICE_PATH + '.*'
        )
    }
    
    stages {
        stage('Checkout') {
            steps {
                checkout([
                    $class: 'GitSCM',
                    branches: [[name: 'main']],
                    userRemoteConfigs: [[
                        url: 'https://github.com/dastmard/YOUR_REPO.git',
                        credentialsId: 'github-credentials'
                    ]]
                ])
            }
        }
        
        stage('Build & Push Image') {
            steps {
                container('kaniko') {
                    sh """
                        /kaniko/executor \
                          --context=dir://${env.SERVICE_PATH} \
                          --dockerfile=${env.SERVICE_PATH}/Dockerfile \
                          --destination=${env.DOCKER_IMAGE}:${BUILD_NUMBER} \
                          --destination=${env.DOCKER_IMAGE}:latest
                    """
                }
            }
        }
        
        stage('Deploy to Kubernetes') {
            steps {
                container('kubectl') {
                    sh """
                        kubectl rollout restart deployment/${env.DEPLOY_NAME} -n ${env.DEPLOY_NAMESPACE}
                        kubectl rollout status deployment/${env.DEPLOY_NAME} -n ${env.DEPLOY_NAMESPACE} --timeout=300s
                    """
                }
            }
        }
    }
    
    post {
        success {
            echo "Successfully deployed ${env.DOCKER_IMAGE}:${BUILD_NUMBER}"
        }
        failure {
            echo "Deployment failed!"
        }
    }
}
```

## GitHub Webhook Setup

1. Go to your GitHub repo → **Settings** → **Webhooks** → **Add webhook**
2. Configure:
   - **Payload URL**: `http://YOUR_JENKINS_IP:30080/generic-webhook-trigger/invoke?token=weekly-sales-store-token`
   - **Content type**: `application/json`
   - **Events**: Select "Just the push event"
3. Click **Add webhook**

## Required Files in Your Repo

Your repo structure should look like:
```
your-repo/
├── services/
│   └── api/
│       └── weekly-sales-store/
│           ├── Dockerfile
│           ├── Jenkinsfile
│           └── (your source code)
```
