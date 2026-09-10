#cloud-config
package_update: true
packages:
  - curl
  - tar
  - libicu74
  - unzip
  - python3
  - python3-pip
runcmd:
  - curl -sL https://aka.ms/InstallAzureCLIDeb | bash
  - useradd -m -s /bin/bash azp || true
  - mkdir -p /home/azp/agent
  - cd /home/azp/agent
  - curl -sSL -o agent.tar.gz https://download.agent.dev.azure.com/agent/${agent_version}/vsts-agent-linux-x64-${agent_version}.tar.gz
  - tar xzf agent.tar.gz
  - chown -R azp:azp /home/azp/agent
  - "su - azp -c 'cd /home/azp/agent && ./config.sh --unattended --url ${azuredevops_org_url} --auth pat --token ${azuredevops_pat} --pool ${agent_pool_name} --agent ${agent_name} --acceptTeeEula --replace'"
  - cd /home/azp/agent
  - ./svc.sh install azp
  - ./svc.sh start
final_message: "The Azure DevOps agent has been configured"