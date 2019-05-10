
//noinspection GroovyAssignabilityCheck
pipeline {
    /* insert Declarative Pipeline here */
    agent { 
        dockerfile {
            filename 'Dockerfile'
            reuseNode true
        }  
    }
    options{
        buildDiscarder( logRotator(numToKeepStr:'10'))
    }
    parameters {
        // Build options
        choice(name: 'config_file', choices:['ci.yml', 'deploy.yml', 'test-vpc.yml'], description:'Config file to use for build defaults')
        string(name: 'region', defaultValue: '-', description: 'Region to host Openshift cluster in')
        string(name: 'redhat_credentials', defaultValue: 'MCPaaSdev', description: 'id of redhat credentials to use for this build e.g. redhat-irichardso22')
        choice(name: 'destroy_on_failure', choices:['-', 'yes', 'no'], description: 'destroy the stack if build fails')
        choice(name: 'destroy_on_complete', choices:['-', 'yes', 'no'], description: 'destroy the stack after the build completes')
        choice(name: 'destroy_on_test_failure', choices:['-', 'yes', 'no'], description: 'destroy the stack if tests fail')
        
        // Quickstart parameters
        string(name: 'AvailabilityZones', defaultValue: '-', description: 'Availability Zones within region to host cluster')
        string(name: 'MasterInstanceType', defaultValue: '-', description: 'The type/size of instance to used for master (defaults to m4.xlarge if unspecified)')
        string(name: 'EtcdInstanceType', defaultValue: '-', description: 'The type/size of instance to use for etcd (defaults to m4.xlarge if unspecified)')
        string(name: 'NodesInstanceType', defaultValue: '-', description: 'The type/size of instance to use for nodes (defaults to m4.xlarge if unspecified)')
        string(name: 'NumberOfNodes', defaultValue: '-', description: 'Number of app nodes to instantiate')
        string(name: 'RedhatSubscriptionPoolID', defaultValue: '-', description: 'redhat subscription pool to use')
    }

    environment{
        BUILD_FILE = "configs/${BRANCH_NAME}-build-config-${BUILD_NUMBER}.yml"
        TEST_HAS_FAILED = 'false'
    }

    stages {
        stage('Get Git Commit Message') {
            environment {
                GITHUB_TOKEN_GENERAL='mcpocp_dxcgithub_token'           
            }  
            steps {
                sh 'set'
                //echo "${currentBuild.buildCauses('hudson.model.Cause$UserIdCause')}" // same as currentBuild.getBuildCauses()
                withCredentials([string(credentialsId: "${env.GITHUB_TOKEN_GENERAL}", variable: 'git_token')]) {
                    script{
                    def isStartedByUserData ='NAN';
                    def isStartedByUser = 'Empty';
                    
                    try {
                        isStartedByUserData = currentBuild.buildCauses;
                        isStartedByUser = isStartedByUserData.shortDescription;
                    }catch(Exception ex){
                        isStartedByUser = 'Empty';
                    } finally {
                        println(isStartedByUser);
                    }
                    if ( isStartedByUser =~ 'Started by user' ){
                        env.buildNow = 'Yes';
                    }else{
                        env.buildNow = 'No'; 
                    }
                    if (env.BRANCH_NAME == 'master' || env.BRANCH_NAME == 'develop'  || env.BRANCH_NAME =~ 'release' || env.BRANCH_NAME =~ 'PR'  ) {
                        env.GIT_COMMIT_MESSAGE = '#createPR'
                    }else{                
                        env.GIT_COMMIT_MESSAGE = sh (returnStdout: true, script: 'git log -1 --format=%B ${GIT_COMMIT}').trim()
                    }
                    if ( env.CHANGE_AUTHOR == null ){
                        def GETCOMMITURL=env.GIT_URL.replace('.git','').replace('github.dxc.com/','github.dxc.com/api/v3/repos/')+'/commits/'+env.GIT_COMMIT+'?access_token='+git_token
                        // get requestor for commit 
                        println('GETCOMMITURL: '+GETCOMMITURL)  
                        getCOMMIT = sh(script: "curl -X GET '${GETCOMMITURL}' -H 'Accept: application/vnd.github.v3+json'", returnStdout: true)           
                        def jsonCOMMIT = readJSON text: getCOMMIT
                        if ( jsonCOMMIT.author != null ){
                        env.CHANGE_AUTHOR=jsonCOMMIT.author.login                  
                        }else{
                        error("Unable to find requestor from github last commit!")
                        }    
                    }  
                    
                    println('Requestor: '+env.CHANGE_AUTHOR)  
                    println('Last GIT commit message: '+env.GIT_COMMIT_MESSAGE)
                    
                    //test
                    }
                }  
            }
            post{ 
                unsuccessful { 
                    office365ConnectorSend message: "Unable to get Git Commit Info: ${env.BUILD_TAG}", webhookUrl: "https://outlook.office.com/webhook/631ebc72-e640-4485-80bd-da4146cc2e60@93f33571-550f-43cf-b09f-cd331338d086/JenkinsCI/b25b1887f66a438ba8db186b3e1ac624/fa3b74e8-d948-46d4-bf3b-b86611edd2fb"
                }
            }
        }  
        stage('Create build config file') {
            when {
                anyOf {
                expression { env.GIT_COMMIT_MESSAGE =~ '#createPR' }
                expression { env.GIT_COMMIT_MESSAGE =~ '#runBuild' }
                expression { env.buildNow =~ 'Yes' }
                }
            }    
            steps {
                withCredentials([
                    string(credentialsId: 'console_pass', variable: 'console_pass'), 
                    string(credentialsId: 'ip_range', variable: 'ip_range'),
                    usernamePassword(credentialsId: "${params.redhat_credentials}", usernameVariable: 'rhsub_user', passwordVariable: 'rhsub_pass')]) 
                {
                    script {
                        // Read chosen yaml file
                        def configData = readYaml file: "configs/${params.config_file}"
                        
                        // Assign any overriden options/parameters
                        params.each { key, value -> 
                            if (value != '-' && configData.options[key] != null)
                            {
                                configData.options[key] = value
                            }
                            
                            if (value != '-' && configData.params[key] != null)
                            {
                                configData.params[key] = value
                            }
                        }

                        // Append branch name and build number to stack name and bucket name
                        configData.options.stack_name += "-${BRANCH_NAME.replace('.','')}-${BUILD_NUMBER}"
                        configData.params.QSS3BucketName += "-${BRANCH_NAME.toLowerCase().replace('.','')}-${BUILD_NUMBER}"

                        // Fill in credential info
                        configData.params.RedhatSubscriptionUserName = rhsub_user
                        configData.params.RedhatSubscriptionPassword = rhsub_pass
                        configData.params.RemoteAccessCIDR = ip_range
                        configData.params.ContainerAccessCIDR = ip_range
                        configData.params.OpenShiftAdminPassword = console_pass

                        // Write result to build file
                        writeYaml file:"${BUILD_FILE}", data:configData
                        sh "cat ${BUILD_FILE}"
                    }
                }
            }
            post{ 
                unsuccessful { 
                    office365ConnectorSend message: "Create build config file stage failed for: ${env.BUILD_TAG}", webhookUrl: "https://outlook.office.com/webhook/631ebc72-e640-4485-80bd-da4146cc2e60@93f33571-550f-43cf-b09f-cd331338d086/JenkinsCI/b25b1887f66a438ba8db186b3e1ac624/fa3b74e8-d948-46d4-bf3b-b86611edd2fb"
                }
            } 
        }
        stage('Deploy openshift (ansible)') {
            when {
                anyOf {
                expression { env.GIT_COMMIT_MESSAGE =~ '#createPR' }
                expression { env.GIT_COMMIT_MESSAGE =~ '#runBuild' }
                expression { env.buildNow =~ 'Yes' }
                }
            }   
            steps {
                withCredentials([
                    [   $class           : 'AmazonWebServicesCredentialsBinding',
                        credentialsId    : "mcpocp_aws_credentials_ocp",
                        accessKeyVariable: 'AWS_ACCESS_KEY_ID',
                        secretKeyVariable: 'AWS_SECRET_ACCESS_KEY' ]
                ]) 
                {
                    ansiblePlaybook(
                        colorized: true,
                        playbook: 'playbooks/create_openshift_stack_cloudformation.yml',
                        extras: "-e @${BUILD_FILE}"
                    )
                }
            }
        }
        stage('Tests') { 
            when {
                anyOf {
                expression { env.GIT_COMMIT_MESSAGE =~ '#createPR' }
                expression { env.GIT_COMMIT_MESSAGE =~ '#runBuild' }
                expression { env.buildNow =~ 'Yes' }
                }
            }   
            steps {
                withCredentials([
                    [   $class           : 'AmazonWebServicesCredentialsBinding',
                        credentialsId    : "mcpocp_aws_credentials_ocp",
                        accessKeyVariable: 'AWS_ACCESS_KEY_ID',
                        secretKeyVariable: 'AWS_SECRET_ACCESS_KEY' ],
                        sshUserPrivateKey(credentialsId: "ocppair", keyFileVariable: 'ocppair_var'),
                        //usernamePassword(credentialsId: 'mcpocp_dxcgithub_token', usernameVariable: 'git_user', passwordVariable: 'git_token')
                        string(credentialsId: 'mcpocp_dxcgithub_token', variable: 'git_token')
                ]) 
                {
                    script {
                        try {
                            ansiblePlaybook(
                                colorized: true,
                                playbook: 'playbooks/run_ansible_tests.yml',
                                extras: '-e @${BUILD_FILE} -e ocppair_f=${ocppair_var} -e token=${git_token}'
                            )
                        }catch(err) {
                            TEST_HAS_FAILED = 'true';
                            office365ConnectorSend message: "Test stage failed for: ${env.BUILD_TAG}", webhookUrl: "https://outlook.office.com/webhook/631ebc72-e640-4485-80bd-da4146cc2e60@93f33571-550f-43cf-b09f-cd331338d086/JenkinsCI/b25b1887f66a438ba8db186b3e1ac624/fa3b74e8-d948-46d4-bf3b-b86611edd2fb"
                        }
                    }
                }
            }
            post{ 
                // this shouldn't be triggered anymore
                unsuccessful { 
                    office365ConnectorSend message: "Test Stage failed for: ${env.BUILD_TAG}", webhookUrl: "https://outlook.office.com/webhook/631ebc72-e640-4485-80bd-da4146cc2e60@93f33571-550f-43cf-b09f-cd331338d086/JenkinsCI/b25b1887f66a438ba8db186b3e1ac624/fa3b74e8-d948-46d4-bf3b-b86611edd2fb"
                }
            } 
        }
        stage('Remove cluster') {
            when {
                anyOf {
                expression { env.GIT_COMMIT_MESSAGE =~ '#createPR' }
                expression { env.GIT_COMMIT_MESSAGE =~ '#runBuild' }
                expression { env.buildNow =~ 'Yes' }
                }
            }   
            steps {
                withCredentials([
                    [   $class           : 'AmazonWebServicesCredentialsBinding',
                        credentialsId    : "mcpocp_aws_credentials_ocp",
                        accessKeyVariable: 'AWS_ACCESS_KEY_ID',
                        secretKeyVariable: 'AWS_SECRET_ACCESS_KEY' ]
                ]) 
                {
                    ansiblePlaybook(
                        colorized: true,
                        playbook: 'playbooks/remove_stack.yml',
                        extras: "-e @${BUILD_FILE} -e test_failure=${TEST_HAS_FAILED}"
                    )
                }
            }
            post{ 
                unsuccessful { 
                    office365ConnectorSend message: "Cluster removal stage failed for: ${env.BUILD_TAG}", webhookUrl: "https://outlook.office.com/webhook/631ebc72-e640-4485-80bd-da4146cc2e60@93f33571-550f-43cf-b09f-cd331338d086/JenkinsCI/b25b1887f66a438ba8db186b3e1ac624/fa3b74e8-d948-46d4-bf3b-b86611edd2fb"
                }
            }
        }
        stage('Test evaluation') {
            when {
                expression { TEST_HAS_FAILED == 'true' }
                anyOf {
                expression { env.GIT_COMMIT_MESSAGE =~ '#createPR' }
                expression { env.GIT_COMMIT_MESSAGE =~ '#runBuild' }
                expression { env.buildNow =~ 'Yes' }
                }
            }   
            steps {
                error("Tests have failed, therefore failing the pipeline.")
            }
        }
        stage('Run GitFlow') {
            when {
                expression { TEST_HAS_FAILED == 'false' }
                anyOf {
                expression { env.GIT_COMMIT_MESSAGE =~ '#createPR' }
                expression { env.BRANCH_NAME == 'develop' }
                expression { env.BRANCH_NAME =~ 'release' }
                }
            }
            environment {
                GITHUB_TOKEN_PERSONAL= "${env.CHANGE_AUTHOR}"+'_dxcgithub_token'           
            }   
            steps {
                sh 'printenv'
                withCredentials([string(credentialsId: "${env.GITHUB_TOKEN_PERSONAL}", variable: 'git_token')]) {
                script{
                    if ( env.BRANCH_NAME =~ 'PR'  || env.BRANCH_NAME =~ 'master' ){
                        //do nothing, when PR or master, do not call gitflow, 146
                    }else{  
                        env.NOTIF_MESSAGE = ''
                        if ( env.BRANCH_NAME != 'master' && !env.BRANCH_NAME.startsWith('release') && env.BRANCH_NAME != 'develop' ){
                            targetBranch='develop'
                        }else if ( env.BRANCH_NAME == 'develop' ){
                            targetBranch='release-3.11'
                        }else if ( env.BRANCH_NAME =~ 'release' ){
                            targetBranch='master'
                        }else{
                            targetBranch='' 
                        }


                        println('SourceBranch: '+env.BRANCH_NAME)
                        println('TargetBranch: '+targetBranch)
                        //https://jenkins.platformdxc.com/job/MCP-OCP/job/dummyrepo/pipeline-syntax/globals
                        //https://www.theserverside.com/blog/Coffee-Talk-Java-News-Stories-and-Opinions/Complete-Jenkins-Git-environment-variables-list-for-batch-jobs-and-shell-script-builds

                        //get reviewers
                        reviewersBTV = sh(script: "curl -X GET 'https://github.dxc.com/api/v3/teams/1279/members?access_token=$git_token' -H 'Accept: application/vnd.github.v3+json'", returnStdout: true) 
                        Random rndBTV = new Random()
                        def jsonBTV = readJSON text: reviewersBTV
                        reviewerBTV=(jsonBTV[rndBTV.nextInt(jsonBTV.size())].login)

                        
                        reviewersNC = sh(script: "curl -X GET 'https://github.dxc.com/api/v3/teams/1145/members?access_token=$git_token' -H 'Accept: application/vnd.github.v3+json'", returnStdout: true) 
                        Random rndNC = new Random()
                        def jsonNC = readJSON text: reviewersNC
                        reviewerNC=(jsonNC[rndNC.nextInt(jsonNC.size())].login)

                        
                        //approver is Milos
                        
                        def reviewerMaster='mhorvat'
                        def PRURL=env.GIT_URL.replace('.git','').replace('github.dxc.com/','github.dxc.com/api/v3/repos/')+'/pulls?access_token='+git_token
                        // do PR 
                        createPR = sh(script: "curl -X POST ${PRURL} -H 'Accept: application/vnd.github.v3+json' -H 'Content-Type: application/json' -d '{   \"title\": \"${env.BRANCH_NAME}\",    \"head\": \"${env.BRANCH_NAME}\",   \"base\": \"${targetBranch}\" }'", returnStdout: true)           
                        def jsonPR = readJSON text: createPR
                        if ( jsonPR.html_url != null ){
                            println('PR URL: '+jsonPR.html_url)
                            println('PR API URL: '+jsonPR.url)
                            //def requestor=jsonPR.user.login

                            while ( env.CHANGE_AUTHOR == reviewerNC){
                                reviewerNC=(jsonNC[rndNC.nextInt(jsonNC.size())].login)
                            }

                            while ( env.CHANGE_AUTHOR == reviewerBTV){
                                reviewerBTV=(jsonBTV[rndBTV.nextInt(jsonBTV.size())].login)
                            }

                            env.NOTIF_MESSAGE = env.NOTIF_MESSAGE+'PR create '+jsonPR.html_url
                            env.NOTIF_MESSAGE = env.NOTIF_MESSAGE+' requestor: '+env.CHANGE_AUTHOR+'\n'
                            if ( targetBranch == 'master' ){
                                env.NOTIF_MESSAGE = env.NOTIF_MESSAGE+'reviewers: '+reviewerMaster
                            }else{
                                env.NOTIF_MESSAGE = env.NOTIF_MESSAGE+'reviewers: '+reviewerNC+','+reviewerBTV 
                            }

                            def UPRURL=jsonPR.url+'/requested_reviewers?access_token='+git_token
                            if ( targetBranch == 'master' ){
                                updatePR = sh(script: "curl -X POST ${UPRURL} -H 'Accept: application/vnd.github.v3+json' -H 'Content-Type: application/json' -d '{   \"reviewers\": [ \"${reviewerMaster}\"]  }'", returnStdout: true)
                            }else{
                                updatePR = sh(script: "curl -X POST ${UPRURL} -H 'Accept: application/vnd.github.v3+json' -H 'Content-Type: application/json' -d '{   \"reviewers\": [ \"${reviewerBTV}\", \"${reviewerNC}\"]  }'", returnStdout: true)              
                            }
                            if ( updatePR.number == null ){
                                env.NOTIF_MESSAGE = env.NOTIF_MESSAGE+ 'Update PR Error: '+updatePR
                            }  
                        }else{
                            env.NOTIF_MESSAGE = env.NOTIF_MESSAGE+ 'Update PR Error: '+jsonPR
                        }
                        
                        if ( env.BRANCH_NAME =~ 'release' ){
                            def REURL=env.GIT_URL.replace('.git','').replace('github.dxc.com/','github.dxc.com/api/v3/repos/')+'/releases?access_token='+git_token
                            releases = sh(script: "curl -X GET ${REURL} -H 'Accept: application/vnd.github.v3+json'", returnStdout: true) 
                            def jsonReleases = readJSON text: releases
                            def releaseNr=env.BRANCH_NAME.replace('release-','');
                            def releaseInitVersion=releaseNr+'-'+'0.0.0';
                            jsonReleases.each { 
                                println(it.tag_name)
                                if (  it.target_commitish == env.BRANCH_NAME ){
                                    releaseInitVersionNr=(releaseInitVersion.replace(releaseNr+'-','')).replace('.','').toInteger();
                                    tag_nameVersionNr=(it.tag_name.replace(releaseNr+'-','')).replace('.','').toInteger();
                                    if ( tag_nameVersionNr > releaseInitVersionNr ){
                                        releaseInitVersion = it.tag_name;
                                    }
                                }
                            }
                            releaseVersionNr=(releaseInitVersion.replace(releaseNr+'-','')).replace('.','').toInteger(); 
                            releaseVersionNrFormat=String.format("%03d", releaseVersionNr+1)
                            tag_name=releaseNr+'-'+releaseVersionNrFormat.substring(0,1)+'.'+releaseVersionNrFormat.substring(1,2)+'.'+releaseVersionNrFormat.substring(2); //.split(/\d+/);
                            println(tag_name);
                            createRelease = sh(script: "curl -X POST ${REURL} -H 'Accept: application/vnd.github.v3+json' -H 'Content-Type: application/json' -d '{ \"tag_name\": \"${tag_name}\",   \"target_commitish\": \"${env.BRANCH_NAME}\",   \"name\": \"${tag_name}\" }'", returnStdout: true)
                            println(createRelease);
                        }  
              //
                    }
                }  
            }
            }
            post{ 
                success { 
                    office365ConnectorSend message: "GitFlow: ${env.NOTIF_MESSAGE}", webhookUrl: "https://outlook.office.com/webhook/631ebc72-e640-4485-80bd-da4146cc2e60@93f33571-550f-43cf-b09f-cd331338d086/JenkinsCI/b25b1887f66a438ba8db186b3e1ac624/fa3b74e8-d948-46d4-bf3b-b86611edd2fb"
                }
                failure {
                    office365ConnectorSend message: "GitFlow stage failed, pls check details in PDXC jenkins", webhookUrl: "https://outlook.office.com/webhook/631ebc72-e640-4485-80bd-da4146cc2e60@93f33571-550f-43cf-b09f-cd331338d086/JenkinsCI/b25b1887f66a438ba8db186b3e1ac624/fa3b74e8-d948-46d4-bf3b-b86611edd2fb"
                }
            }
        }     
    }        
}
