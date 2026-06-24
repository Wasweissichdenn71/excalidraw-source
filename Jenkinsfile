pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
        skipDefaultCheckout(false)
    }

    triggers {
        pollSCM('H/2 * * * *')
    }

    environment {
        TARGET_REPO = 'git@github.com:Wasweissichdenn71/excalidraw-export.git'
        TARGET_BRANCH = 'main'
        EXPORT_DIR = 'exports'
        PLAYWRIGHT_BROWSERS_PATH = '/var/lib/jenkins/.cache/ms-playwright'
        HOME = '/var/lib/jenkins'
    }

    stages {
        stage('Verify tools') {
            steps {
                sh '''
                    git --version
                    python3 --version
                    node --version
                    npm --version
                    inkscape --version
                    excalidraw-brute-export-cli --help | head -5
                    test -d "$PLAYWRIGHT_BROWSERS_PATH"
                '''
            }
        }

        stage('Checkout target repository') {
            steps {
                sshagent(credentials: ['excalidraw-git-ssh']) {
                    sh '''
                        rm -rf target
                        mkdir -p ~/.ssh
                        chmod 700 ~/.ssh
                        ssh-keyscan -H github.com >> ~/.ssh/known_hosts

                        git clone --branch "$TARGET_BRANCH" "$TARGET_REPO" target
                    '''
                }
            }
        }

        stage('Convert Excalidraw files') {
            steps {
                sh '''
                    rm -rf "target/$EXPORT_DIR"
                    mkdir -p "target/$EXPORT_DIR"

                    bash ci/export_excalidraw.sh \
                      "$WORKSPACE" \
                      "$WORKSPACE/target/$EXPORT_DIR"
                '''
            }
        }

        stage('Commit and push exports') {
            steps {
                sshagent(credentials: ['excalidraw-git-ssh']) {
                    sh '''
                        cd target

                        git config user.name "jenkins"
                        git config user.email "jenkins@local"

                        git add "$EXPORT_DIR"

                        if [ -z "$(git status --porcelain)" ]; then
                            echo "Keine Änderungen im Export-Repo."
                            exit 0
                        fi

                        git commit -m "Update Excalidraw exports from Jenkins build ${BUILD_NUMBER}"
                        git push origin "HEAD:$TARGET_BRANCH"
                    '''
                }
            }
        }
    }

    post {
        always {
            archiveArtifacts artifacts: 'target/exports/**/*', allowEmptyArchive: true
        }
    }
}
