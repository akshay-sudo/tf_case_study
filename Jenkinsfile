pipeline {
    agent any
    
    parameters {
        string(name: 'AWS_REGION', defaultValue: 'us-east-1', description: 'AWS Region to deploy resources')
        string(name: 'PROJECT_NAME', defaultValue: 'webserver-project', description: 'Project name')
        string(name: 'VPC_CIDR', defaultValue: '10.0.0.0/16', description: 'CIDR block for VPC')
        string(name: 'KEY_NAME', defaultValue: 'webserver-key', description: 'SSH key pair name')
    }
    
    environment {
        TF_IN_AUTOMATION = 'true'
    }
    
    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }
        
        stage('Install Dependencies') {
            steps {
                sh '''
                    # Install Terraform
                    if ! command -v terraform &> /dev/null; then
                        wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg
                        echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
                        sudo apt-get update && sudo apt-get install -y terraform
                    fi
                    
                    # Install Ansible
                    if ! command -v ansible &> /dev/null; then
                        sudo apt-get update && sudo apt-get install -y ansible
                    fi
                    
                    # Install AWS CLI
                    if ! command -v aws &> /dev/null; then
                        curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
                        unzip awscliv2.zip
                        sudo ./aws/install
                    fi
                '''
            }
        }
        
        stage('Terraform Init') {
            steps {
                sh 'terraform init'
            }
        }
        
        stage('Terraform Plan') {
            steps {
                sh """
                    terraform plan \
                    -var="aws_region=${params.AWS_REGION}" \
                    -var="project_name=${params.PROJECT_NAME}" \
                    -var="vpc_cidr=${params.VPC_CIDR}" \
                    -var="key_name=${params.KEY_NAME}" \
                    -out=tfplan
                """
            }
        }
        
        stage('Terraform Apply') {
            steps {
                sh 'terraform apply -auto-approve tfplan'
            }
        }
    }
    
    post {
        success {
            echo 'Infrastructure successfully deployed!'
        }
        failure {
            echo 'Infrastructure deployment failed!'
        }
        cleanup {
            sh 'rm -f tfplan'
        }
    }
}
