AWS Serverless Data Lake Workshop Documentation

Reference workshop: [AWS Serverless Data Lake Workshop](https://catalog.us-east-1.prod.workshops.aws/workshops/ea7ddf16-5e0a-4ec7-b54e-5cadf3028b78/en-US)

1. Prerequisites:

    - Folder: 00-setup
    - SDL-Service-Role: **iam-freeconciled.json**
    - IAM user policies: participant-policy.json and participant-guardrails-policy.json
    - In case deploy/destroy using CLI instead of console:
        + cd 00-setup/
        + ./deploy
        + ./destroy

2. Lab 1: Data Ingestion & Storage

    - Follow instruction for Lab 1 in the reference workshop link

3. Lab 2: Lab2 Data Cataloging and ETL

    - Follow instruction for Lab 2 in the reference workshop link

4. Lab 3.1: SQL analytics on a Large Scale Open Dataset

    - Follow instrction for Lab 3.1 in the reference workshop link
    - All queries for this lab is in **./lab3.1/query.sql**

5. Lab 3.2: Bedrock AI Agent with managed Knowledge base

    - This additional lab is conducted completely using IaC, in particularly Terraform.
    - Run the following commands to deploy all infrastructures and your AI agent:
        
        To deploy the Knowledge Base:

        + cd lab3.2/terraform/
        + terraform init
        + terraform plan
        + terraform apply --auto-approve

        Create a .env file, copy the value of KNOWLEDGE_BASE_ID and paste it there

        To deploy your AI agent:

        cd ..
        # 1. Create the project (interactive): enter a name, then choose "Skip"
        agentcore create

        # 2. Move into the project the CLI just created
        cd <project-name>

        # 3. Add your existing agent (interactive): agent -> name ->
        #    "Bring my own code" -> Enter (code location) -> Enter (entrypoint) ->
        #    "Direct Code Deploy" -> "Amazon Bedrock" -> Enter (advanced) -> confirm
        agentcore add

        # 4. Copy your agent code into the app folder the CLI created
        cp ../main.py ../gdelt_tools.py ../steering_handlers.py ../requirements.txt app/MyAgent/

        # 5. Set up dependencies in app/MyAgent/ (creates pyproject.toml + .venv)
        cd app/MyAgent
        uv init --bare --python 3.13
        uv add strands-agents bedrock-agentcore aws-opentelemetry-distro boto3
        cd ../..

        # 6. Test locally, then deploy and invoke
        agentcore dev                                          # local server for testing
        agentcore deploy                                       # package to S3 + provision runtime
        agentcore invoke

        Clean up

        agentcore remove all -y    # clears the local config (does NOT touch AWS yet)
        agentcore deploy           # applies the teardown - removes the runtime from AWS
