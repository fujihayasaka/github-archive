# typed: true
# frozen_string_literal: true

require "test_helper"
require "yaml"

class Codespaces::CreatePrebuildTemplateDynamicWorkflowTest < GitHub::TestCase
  include GitHub::LoggerHelper

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    make_trusted_oauth_apps_owner
    enable_feature_flag(:codespaces_developer)
    disable_feature_flag(:codespaces_prebuilds_new_regions)
    disable_feature_flag(:codespaces_remove_prebuild_artifacts)
    disable_feature_flag(:codespaces_prebuild_forward_vm_agent_feature_flags)
    disable_feature_flag(:codespaces_larger_storage_size)
    disable_feature_flag(:codespaces_prebuilds_skip_v1_upload)

    @actions_app = create(:launch_integration)
    @integration = create(:codespaces_integration)
    @codespaces_bot = @integration.bot

    @user = create(:user)
    @org = create(:organization, plan: GitHub::Plan.business, admin: @user)

    @repository = create(:repository, owner: @org, from_example: :refs_test)
    @repository.add_member(@user)

    @branch = "master"
    @region1 = "WestUs2"
    @region2 = "EastUs"
    @devcontainer_path = ".devcontainer/custom/devcontainer.json"

    @repository.refs.find("master").append_commit({ message: "First!", committer: @repository.owner }, @repository.owner) do |files|
      files.add ".devcontainer/custom/devcontainer.json", <<-JSON # Exclude Basic-tier SKU with 2 cores
        { "hostRequirements": { "cpus": 4 } }
      JSON
    end

    @commit_sha = @repository.refs.find(@branch).sha
    @commit = @repository.commits.find(@commit_sha)
    @concurrency_modifier = "string"

    @prebuild_hash = Codespaces::CalculatePrebuildHash.call(repository: @repository, oid: @commit_sha, devcontainer_path: @devcontainer_path)
    @prebuild_hash_no_devcontainer = Codespaces::CalculatePrebuildHash.call(repository: @repository, oid: @commit_sha, devcontainer_path: nil)

    @configuration = create(:codespace_prebuild_configuration, repository: @repository, branch: @branch)

    @workflow_yaml = build_workflow_yaml_with_devcontainer_path(@commit, @prebuild_hash, @repository, @region1, @configuration, "GitHub", GitHub.host_name_with_tenant, GitHub.api_url, GitHub.graphql_api_url, image_allow_list_policy: "", feature_flags: "")
    @workflow_yaml_no_devcontainer_path = build_workflow_yaml_without_devcontainer_path(@commit, @prebuild_hash_no_devcontainer, @repository, @region1, @configuration, "GitHub", GitHub.host_name_with_tenant, GitHub.api_url, GitHub.graphql_api_url)

    emu = create(:emu)
    @business = emu.enterprise_managed_business

    @tenant_repository = create(:repository, from_example: :refs_test)

    @tenant_branch = "master"

    @tenant_repository.refs.find("master").append_commit({ message: "First!", committer: @tenant_repository.owner }, @tenant_repository.owner) do |files|
      files.add ".devcontainer/custom/devcontainer.json", <<-JSON # Exclude Basic-tier SKU with 2 cores
        { "hostRequirements": { "cpus": 4 } }
      JSON
    end

    @tenant_commit_sha = @tenant_repository.refs.find(@tenant_branch).sha
    @tenant_commit = @tenant_repository.commits.find(@tenant_commit_sha)

    @tenant_prebuild_hash = Codespaces::CalculatePrebuildHash.call(repository: @tenant_repository, oid: @tenant_commit_sha, devcontainer_path: @devcontainer_path)
    @tenant_prebuild_hash_no_devcontainer = Codespaces::CalculatePrebuildHash.call(repository: @tenant_repository, oid: @tenant_commit_sha, devcontainer_path: nil)

    @tenant_configuration = create(:codespace_prebuild_configuration,
      repository: @tenant_repository,
      branch: @tenant_branch
    )

    @workflow_yaml_no_artifacts =
    <<~YAML
    name: "[master]: #{@commit.short_message_text}"
    'on': dynamic
    concurrency: #{@prebuild_hash}-string
    defaults:
      run:
        shell: sudo -EH bash {0}
    jobs:
      prebuild:
        runs-on: codespaces-prebuild
        steps:
        - name: Mask secrets
          run: |
            echo -e $USER_SECRETS_JSON | jq 'del(.[] |
              select(.value=="GitHub" or .value=="noreply@github.com" or .value=="https://github.com" or .value=="https://api.github.com" or .value=="https://api.github.com/graphql" or .value=="#{@repository.nwo}" or .value=="" or .value==null))' |
              jq 'unique_by(.value)' | jq .[] | jq '.value[]? // .value?' |jq -r \\\"::add-mask::\\\"+'.?'
        - name: Install Agent
          run: |
            umount -f /mnt
            set -exu pipefall
            # Download and extract agent
            mkdir -p /.codespaces/agent/bin
            cd /.codespaces/agent/bin
            FIRST_LOCATION=($TARGET_VSCS_LOCATIONS)
            AGENT_DOWNLOAD_URL="#{GitHub.api_url}/$INTERNAL_URL/${{ github.repository }}/agent/download?$TARGET_LOCATION_KEY=$FIRST_LOCATION&workflow_run_id=$CODESPACES_GITHUB__WORKFLOWRUNID&$TARGET_KEY=$CODESPACES_GITHUB__VSCSTARGET&$TARGET_URL_KEY=${CODESPACES_GITHUB__VSCSTARGETURL-}"
            curl --location $AGENT_DOWNLOAD_URL \
              --header "Authorization: token $CODESPACES_GITHUB__APITOKEN" \
              --output tmp.zip
            unzip -q tmp.zip && rm tmp.zip
            # Install agent
            containerTmp=/mnt/containerTmp
            mkdir -p $containerTmp
            chmod o+rwt $containerTmp
            setfacl -dR -m o::rw $containerTmp
            codespacesSharedFolder=~/.codespaces/shared
            mkdir -p $codespacesSharedFolder
            chmod o+rw $codespacesSharedFolder
            setfacl -dR -m o::rw $codespacesSharedFolder
            chmod +x install_codespaces_agent.sh
            ./install_codespaces_agent.sh
            # Make copy of codespaces agent to mount
            mkdir -p /.codespaces/agent/mount
            cp -a /.codespaces/agent/bin/. /.codespaces/agent/mount
        - name: Create Template
          run: |
            # Create
            /.codespaces/agent/bin/codespaces prebuild create --repo-url $REPO_URL_WITHOUT_BRANCH --repo-name-no-owner $REPO_NAME_WITHOUT_OWNER --branch ${{ github.ref_name }} --devcontainer-path $DEVCONTAINER_PATH --commit ${{ github.sha }} --config-id $CONFIGURATION_ID --user-secrets-env USER_SECRETS_JSON
        - name: Upload Template
          run: |
            for location in $TARGET_VSCS_LOCATIONS; do
              /.codespaces/agent/bin/codespaces prebuild upload --location $location --repo-name ${{ github.repository }} --devcontainer-path $DEVCONTAINER_PATH --config-id $CONFIGURATION_ID
            done
        env:
          CODESPACES_GITHUB__APITOKEN: "${{ secrets.GITHUB_TOKEN }}"
          CODESPACES_GITHUB__VSCSTARGET: production
          CODESPACES_GITHUB__WORKFLOWRUNID: "${{ github.run_id }}"
          CODESPACES_GITHUB__APIURLBASE: #{GitHub.api_url}
          CODESPACES_TELEMETRYSETTINGS__TELEMETRYENDPOINT: "${{ secrets.GITHUB_CODESPACES_INTERNAL_URL }}/${{ github.repository }}/agent/diagnostics"
          TARGET_VSCS_LOCATIONS: #{@region1}
          USER_SECRETS_JSON: "${{secrets.GITHUB_CODESPACE_AGENT_SECRETS}}"
          REPO_URL: "${{ github.server_url }}/${{ github.repository }}/tree/${{ github.ref_name }}"
          REPO_URL_WITHOUT_BRANCH: "${{ github.server_url }}/${{ github.repository }}"
          REPO_NAME_WITHOUT_OWNER: #{@repository.name}
          DEVCONTAINER_PATH: ".devcontainer/custom/devcontainer.json"
          CONFIGURATION_ID: #{@configuration.id}
          CODESPACES_GITHUB__VSCSTARGETURL: ''
          INTERNAL_URL: "${{ secrets.GITHUB_CODESPACES_INTERNAL_URL }}"
          LOG_PATH: "${{ secrets.GITHUB_CODESPACES_LOG_PATH}}"
          TARGET_KEY: "${{ secrets.GITHUB_CODESPACES_TARGET_KEY }}"
          TARGET_LOCATION_KEY: "${{ secrets.GITHUB_CODESPACES_LOCATION_KEY }}"
          TARGET_URL_KEY: "${{ secrets.GITHUB_CODESPACES_TARGET_URL_KEY }}"
    YAML

    @workflow_yaml_storage_v2 =
    <<~YAML
    name: "[master]: #{@commit.short_message_text}"
    'on': dynamic
    concurrency: #{@prebuild_hash}-string
    defaults:
      run:
        shell: sudo -EH bash {0}
    jobs:
      prebuild:
        runs-on: codespaces-prebuild
        steps:
        - name: Mask secrets
          run: |
            echo -e $USER_SECRETS_JSON | jq 'del(.[] |
              select(.value=="GitHub" or .value=="noreply@github.com" or .value=="https://github.com" or .value=="https://api.github.com" or .value=="https://api.github.com/graphql" or .value=="#{@repository.nwo}" or .value=="" or .value==null))' |
              jq 'unique_by(.value)' | jq .[] | jq '.value[]? // .value?' |jq -r \\\"::add-mask::\\\"+'.?'
        - name: Install Agent
          run: |
            umount -f /mnt
            set -exu pipefall
            # Download and extract agent
            mkdir -p /.codespaces/agent/bin
            cd /.codespaces/agent/bin
            FIRST_LOCATION=($TARGET_VSCS_LOCATIONS)
            AGENT_DOWNLOAD_URL="#{GitHub.api_url}/$INTERNAL_URL/${{ github.repository }}/agent/download?$TARGET_LOCATION_KEY=$FIRST_LOCATION&workflow_run_id=$CODESPACES_GITHUB__WORKFLOWRUNID&$TARGET_KEY=$CODESPACES_GITHUB__VSCSTARGET&$TARGET_URL_KEY=${CODESPACES_GITHUB__VSCSTARGETURL-}"
            curl --location $AGENT_DOWNLOAD_URL \
              --header "Authorization: token $CODESPACES_GITHUB__APITOKEN" \
              --output tmp.zip
            unzip -q tmp.zip && rm tmp.zip
            # Install agent
            containerTmp=/mnt/containerTmp
            mkdir -p $containerTmp
            chmod o+rwt $containerTmp
            setfacl -dR -m o::rw $containerTmp
            codespacesSharedFolder=~/.codespaces/shared
            mkdir -p $codespacesSharedFolder
            chmod o+rw $codespacesSharedFolder
            setfacl -dR -m o::rw $codespacesSharedFolder
            chmod +x install_codespaces_agent.sh
            ./install_codespaces_agent.sh
            # Make copy of codespaces agent to mount
            mkdir -p /.codespaces/agent/mount
            cp -a /.codespaces/agent/bin/. /.codespaces/agent/mount
        - name: Create Template
          run: |
            # Create
            /.codespaces/agent/bin/codespaces prebuild create --repo-url $REPO_URL_WITHOUT_BRANCH --repo-name-no-owner $REPO_NAME_WITHOUT_OWNER --branch ${{ github.ref_name }} --devcontainer-path $DEVCONTAINER_PATH --commit ${{ github.sha }} --config-id $CONFIGURATION_ID --user-secrets-env USER_SECRETS_JSON --storage-size 256
        - name: Upload Template
          run: |
            for location in $TARGET_VSCS_LOCATIONS; do
              /.codespaces/agent/bin/codespaces prebuild upload --location $location --repo-name ${{ github.repository }} --devcontainer-path $DEVCONTAINER_PATH --config-id $CONFIGURATION_ID
            done
            # Generate manifest
            /.codespaces/agent/bin/codespaces prebuild manifest --config-id $CONFIGURATION_ID
            # Upload templates
            /.codespaces/agent/bin/codespaces prebuild upload --storage-type v2 --target-locations WestUs2 --repo-name ${{ github.repository }} --devcontainer-path $DEVCONTAINER_PATH --config-id $CONFIGURATION_ID --flush-only --image-version Minimal
        - name: Save Creation Logs
          if: always()
          uses: actions/upload-artifact@v2
          with:
            name: logs
            path: "${{ env.LOG_PATH }}"
        env:
          CODESPACES_GITHUB__APITOKEN: "${{ secrets.GITHUB_TOKEN }}"
          CODESPACES_GITHUB__VSCSTARGET: production
          CODESPACES_GITHUB__WORKFLOWRUNID: "${{ github.run_id }}"
          CODESPACES_GITHUB__APIURLBASE: #{GitHub.api_url}
          CODESPACES_TELEMETRYSETTINGS__TELEMETRYENDPOINT: "${{ secrets.GITHUB_CODESPACES_INTERNAL_URL }}/${{ github.repository }}/agent/diagnostics"
          TARGET_VSCS_LOCATIONS: #{@region1}
          USER_SECRETS_JSON: "${{secrets.GITHUB_CODESPACE_AGENT_SECRETS}}"
          REPO_URL: "${{ github.server_url }}/${{ github.repository }}/tree/${{ github.ref_name }}"
          REPO_URL_WITHOUT_BRANCH: "${{ github.server_url }}/${{ github.repository }}"
          REPO_NAME_WITHOUT_OWNER: #{@repository.name}
          DEVCONTAINER_PATH: ".devcontainer/custom/devcontainer.json"
          CONFIGURATION_ID: #{@configuration.id}
          CODESPACES_GITHUB__VSCSTARGETURL: ''
          INTERNAL_URL: "${{ secrets.GITHUB_CODESPACES_INTERNAL_URL }}"
          LOG_PATH: "${{ secrets.GITHUB_CODESPACES_LOG_PATH}}"
          TARGET_KEY: "${{ secrets.GITHUB_CODESPACES_TARGET_KEY }}"
          TARGET_LOCATION_KEY: "${{ secrets.GITHUB_CODESPACES_LOCATION_KEY }}"
          TARGET_URL_KEY: "${{ secrets.GITHUB_CODESPACES_TARGET_URL_KEY }}"
    YAML

    @workflow_yaml_storage_v2_no_devcontainer_path =
    <<~YAML
    name: "[master]: #{@commit.short_message_text}"
    'on': dynamic
    concurrency: #{@prebuild_hash_no_devcontainer}-string
    defaults:
      run:
        shell: sudo -EH bash {0}
    jobs:
      prebuild:
        runs-on: codespaces-prebuild
        steps:
        - name: Mask secrets
          run: |
            echo -e $USER_SECRETS_JSON | jq 'del(.[] |
              select(.value=="GitHub" or .value=="noreply@github.com" or .value=="https://github.com" or .value=="https://api.github.com" or .value=="https://api.github.com/graphql" or .value=="#{@repository.nwo}" or .value=="" or .value==null))' |
              jq 'unique_by(.value)' | jq .[] | jq '.value[]? // .value?' |jq -r \\\"::add-mask::\\\"+'.?'
        - name: Install Agent
          run: |
            umount -f /mnt
            set -exu pipefall
            # Download and extract agent
            mkdir -p /.codespaces/agent/bin
            cd /.codespaces/agent/bin
            FIRST_LOCATION=($TARGET_VSCS_LOCATIONS)
            AGENT_DOWNLOAD_URL="#{GitHub.api_url}/$INTERNAL_URL/${{ github.repository }}/agent/download?$TARGET_LOCATION_KEY=$FIRST_LOCATION&workflow_run_id=$CODESPACES_GITHUB__WORKFLOWRUNID&$TARGET_KEY=$CODESPACES_GITHUB__VSCSTARGET&$TARGET_URL_KEY=${CODESPACES_GITHUB__VSCSTARGETURL-}"
            curl --location $AGENT_DOWNLOAD_URL \
              --header "Authorization: token $CODESPACES_GITHUB__APITOKEN" \
              --output tmp.zip
            unzip -q tmp.zip && rm tmp.zip
            # Install agent
            containerTmp=/mnt/containerTmp
            mkdir -p $containerTmp
            chmod o+rwt $containerTmp
            setfacl -dR -m o::rw $containerTmp
            codespacesSharedFolder=~/.codespaces/shared
            mkdir -p $codespacesSharedFolder
            chmod o+rw $codespacesSharedFolder
            setfacl -dR -m o::rw $codespacesSharedFolder
            chmod +x install_codespaces_agent.sh
            ./install_codespaces_agent.sh
            # Make copy of codespaces agent to mount
            mkdir -p /.codespaces/agent/mount
            cp -a /.codespaces/agent/bin/. /.codespaces/agent/mount
        - name: Create Template
          run: |
            # Create
            /.codespaces/agent/bin/codespaces prebuild create --repo-url $REPO_URL_WITHOUT_BRANCH --repo-name-no-owner $REPO_NAME_WITHOUT_OWNER --branch ${{ github.ref_name }} --commit ${{ github.sha }} --config-id $CONFIGURATION_ID --user-secrets-env USER_SECRETS_JSON --storage-size 256
        - name: Upload Template
          run: |
            for location in $TARGET_VSCS_LOCATIONS; do
              /.codespaces/agent/bin/codespaces prebuild upload --location $location --repo-name ${{ github.repository }} --config-id $CONFIGURATION_ID
            done
            # Generate manifest
            /.codespaces/agent/bin/codespaces prebuild manifest --config-id $CONFIGURATION_ID
            # Upload templates
            /.codespaces/agent/bin/codespaces prebuild upload --storage-type v2 --target-locations WestUs2 --repo-name ${{ github.repository }} --config-id $CONFIGURATION_ID --flush-only --image-version Minimal
        - name: Save Creation Logs
          if: always()
          uses: actions/upload-artifact@v2
          with:
            name: logs
            path: "${{ env.LOG_PATH }}"
        env:
          CODESPACES_GITHUB__APITOKEN: "${{ secrets.GITHUB_TOKEN }}"
          CODESPACES_GITHUB__VSCSTARGET: production
          CODESPACES_GITHUB__WORKFLOWRUNID: "${{ github.run_id }}"
          CODESPACES_GITHUB__APIURLBASE: #{GitHub.api_url}
          CODESPACES_TELEMETRYSETTINGS__TELEMETRYENDPOINT: "${{ secrets.GITHUB_CODESPACES_INTERNAL_URL }}/${{ github.repository }}/agent/diagnostics"
          TARGET_VSCS_LOCATIONS: #{@region1}
          USER_SECRETS_JSON: "${{secrets.GITHUB_CODESPACE_AGENT_SECRETS}}"
          REPO_URL: "${{ github.server_url }}/${{ github.repository }}/tree/${{ github.ref_name }}"
          REPO_URL_WITHOUT_BRANCH: "${{ github.server_url }}/${{ github.repository }}"
          REPO_NAME_WITHOUT_OWNER: #{@repository.name}
          DEVCONTAINER_PATH: ''
          CONFIGURATION_ID: #{@configuration.id}
          CODESPACES_GITHUB__VSCSTARGETURL: ''
          INTERNAL_URL: "${{ secrets.GITHUB_CODESPACES_INTERNAL_URL }}"
          LOG_PATH: "${{ secrets.GITHUB_CODESPACES_LOG_PATH}}"
          TARGET_KEY: "${{ secrets.GITHUB_CODESPACES_TARGET_KEY }}"
          TARGET_LOCATION_KEY: "${{ secrets.GITHUB_CODESPACES_LOCATION_KEY }}"
          TARGET_URL_KEY: "${{ secrets.GITHUB_CODESPACES_TARGET_URL_KEY }}"
    YAML

    @workflow_yaml_storage_v2_multi_versions =
    <<~YAML
    name: "[master]: #{@commit.short_message_text}"
    'on': dynamic
    concurrency: #{@prebuild_hash}-string
    defaults:
      run:
        shell: sudo -EH bash {0}
    jobs:
      prebuild:
        runs-on: codespaces-prebuild
        steps:
        - name: Mask secrets
          run: |
            echo -e $USER_SECRETS_JSON | jq 'del(.[] |
              select(.value=="GitHub" or .value=="noreply@github.com" or .value=="https://github.com" or .value=="https://api.github.com" or .value=="https://api.github.com/graphql" or .value=="#{@repository.nwo}" or .value=="" or .value==null))' |
              jq 'unique_by(.value)' | jq .[] | jq '.value[]? // .value?' |jq -r \\\"::add-mask::\\\"+'.?'
        - name: Install Agent
          run: |
            umount -f /mnt
            set -exu pipefall
            # Download and extract agent
            mkdir -p /.codespaces/agent/bin
            cd /.codespaces/agent/bin
            FIRST_LOCATION=($TARGET_VSCS_LOCATIONS)
            AGENT_DOWNLOAD_URL="#{GitHub.api_url}/$INTERNAL_URL/${{ github.repository }}/agent/download?$TARGET_LOCATION_KEY=$FIRST_LOCATION&workflow_run_id=$CODESPACES_GITHUB__WORKFLOWRUNID&$TARGET_KEY=$CODESPACES_GITHUB__VSCSTARGET&$TARGET_URL_KEY=${CODESPACES_GITHUB__VSCSTARGETURL-}"
            curl --location $AGENT_DOWNLOAD_URL \
              --header "Authorization: token $CODESPACES_GITHUB__APITOKEN" \
              --output tmp.zip
            unzip -q tmp.zip && rm tmp.zip
            # Install agent
            containerTmp=/mnt/containerTmp
            mkdir -p $containerTmp
            chmod o+rwt $containerTmp
            setfacl -dR -m o::rw $containerTmp
            codespacesSharedFolder=~/.codespaces/shared
            mkdir -p $codespacesSharedFolder
            chmod o+rw $codespacesSharedFolder
            setfacl -dR -m o::rw $codespacesSharedFolder
            chmod +x install_codespaces_agent.sh
            ./install_codespaces_agent.sh
            # Make copy of codespaces agent to mount
            mkdir -p /.codespaces/agent/mount
            cp -a /.codespaces/agent/bin/. /.codespaces/agent/mount
        - name: Create Template
          run: |
            # Create
            /.codespaces/agent/bin/codespaces prebuild create --repo-url $REPO_URL_WITHOUT_BRANCH --repo-name-no-owner $REPO_NAME_WITHOUT_OWNER --branch ${{ github.ref_name }} --devcontainer-path $DEVCONTAINER_PATH --commit ${{ github.sha }} --config-id $CONFIGURATION_ID --user-secrets-env USER_SECRETS_JSON --image-version Minimal --image-version Raw --storage-size 256
        - name: Upload Template
          run: |
            for location in $TARGET_VSCS_LOCATIONS; do
              /.codespaces/agent/bin/codespaces prebuild upload --location $location --repo-name ${{ github.repository }} --devcontainer-path $DEVCONTAINER_PATH --config-id $CONFIGURATION_ID
            done
            # Generate manifest
            /.codespaces/agent/bin/codespaces prebuild manifest --config-id $CONFIGURATION_ID --image-version Minimal --image-version Raw
            # Upload templates
            /.codespaces/agent/bin/codespaces prebuild upload --storage-type v2 --target-locations WestUs2 --repo-name ${{ github.repository }} --devcontainer-path $DEVCONTAINER_PATH --config-id $CONFIGURATION_ID --flush-only --image-version Minimal --image-version Raw
        - name: Save Creation Logs
          if: always()
          uses: actions/upload-artifact@v2
          with:
            name: logs
            path: "${{ env.LOG_PATH }}"
        env:
          CODESPACES_GITHUB__APITOKEN: "${{ secrets.GITHUB_TOKEN }}"
          CODESPACES_GITHUB__VSCSTARGET: production
          CODESPACES_GITHUB__WORKFLOWRUNID: "${{ github.run_id }}"
          CODESPACES_GITHUB__APIURLBASE: #{GitHub.api_url}
          CODESPACES_TELEMETRYSETTINGS__TELEMETRYENDPOINT: "${{ secrets.GITHUB_CODESPACES_INTERNAL_URL }}/${{ github.repository }}/agent/diagnostics"
          TARGET_VSCS_LOCATIONS: #{@region1}
          USER_SECRETS_JSON: "${{secrets.GITHUB_CODESPACE_AGENT_SECRETS}}"
          REPO_URL: "${{ github.server_url }}/${{ github.repository }}/tree/${{ github.ref_name }}"
          REPO_URL_WITHOUT_BRANCH: "${{ github.server_url }}/${{ github.repository }}"
          REPO_NAME_WITHOUT_OWNER: #{@repository.name}
          DEVCONTAINER_PATH: ".devcontainer/custom/devcontainer.json"
          CONFIGURATION_ID: #{@configuration.id}
          CODESPACES_GITHUB__VSCSTARGETURL: ''
          INTERNAL_URL: "${{ secrets.GITHUB_CODESPACES_INTERNAL_URL }}"
          LOG_PATH: "${{ secrets.GITHUB_CODESPACES_LOG_PATH}}"
          TARGET_KEY: "${{ secrets.GITHUB_CODESPACES_TARGET_KEY }}"
          TARGET_LOCATION_KEY: "${{ secrets.GITHUB_CODESPACES_LOCATION_KEY }}"
          TARGET_URL_KEY: "${{ secrets.GITHUB_CODESPACES_TARGET_URL_KEY }}"
    YAML

    @workflow_yaml_storage_v2_raw_only =
    <<~YAML
    name: "[master]: #{@commit.short_message_text}"
    'on': dynamic
    concurrency: #{@prebuild_hash}-string
    defaults:
      run:
        shell: sudo -EH bash {0}
    jobs:
      prebuild:
        runs-on: codespaces-prebuild
        steps:
        - name: Mask secrets
          run: |
            echo -e $USER_SECRETS_JSON | jq 'del(.[] |
              select(.value=="GitHub" or .value=="noreply@github.com" or .value=="https://github.com" or .value=="https://api.github.com" or .value=="https://api.github.com/graphql" or .value=="#{@repository.nwo}" or .value=="" or .value==null))' |
              jq 'unique_by(.value)' | jq .[] | jq '.value[]? // .value?' |jq -r \\\"::add-mask::\\\"+'.?'
        - name: Install Agent
          run: |
            umount -f /mnt
            set -exu pipefall
            # Download and extract agent
            mkdir -p /.codespaces/agent/bin
            cd /.codespaces/agent/bin
            FIRST_LOCATION=($TARGET_VSCS_LOCATIONS)
            AGENT_DOWNLOAD_URL="#{GitHub.api_url}/$INTERNAL_URL/${{ github.repository }}/agent/download?$TARGET_LOCATION_KEY=$FIRST_LOCATION&workflow_run_id=$CODESPACES_GITHUB__WORKFLOWRUNID&$TARGET_KEY=$CODESPACES_GITHUB__VSCSTARGET&$TARGET_URL_KEY=${CODESPACES_GITHUB__VSCSTARGETURL-}"
            curl --location $AGENT_DOWNLOAD_URL \
              --header "Authorization: token $CODESPACES_GITHUB__APITOKEN" \
              --output tmp.zip
            unzip -q tmp.zip && rm tmp.zip
            # Install agent
            containerTmp=/mnt/containerTmp
            mkdir -p $containerTmp
            chmod o+rwt $containerTmp
            setfacl -dR -m o::rw $containerTmp
            codespacesSharedFolder=~/.codespaces/shared
            mkdir -p $codespacesSharedFolder
            chmod o+rw $codespacesSharedFolder
            setfacl -dR -m o::rw $codespacesSharedFolder
            chmod +x install_codespaces_agent.sh
            ./install_codespaces_agent.sh
            # Make copy of codespaces agent to mount
            mkdir -p /.codespaces/agent/mount
            cp -a /.codespaces/agent/bin/. /.codespaces/agent/mount
        - name: Create Template
          run: |
            # Create
            /.codespaces/agent/bin/codespaces prebuild create --repo-url $REPO_URL_WITHOUT_BRANCH --repo-name-no-owner $REPO_NAME_WITHOUT_OWNER --branch ${{ github.ref_name }} --devcontainer-path $DEVCONTAINER_PATH --commit ${{ github.sha }} --config-id $CONFIGURATION_ID --user-secrets-env USER_SECRETS_JSON --image-version Raw --storage-size 256
        - name: Upload Template
          run: |
            for location in $TARGET_VSCS_LOCATIONS; do
              /.codespaces/agent/bin/codespaces prebuild upload --location $location --repo-name ${{ github.repository }} --devcontainer-path $DEVCONTAINER_PATH --config-id $CONFIGURATION_ID
            done
            # Generate manifest
            /.codespaces/agent/bin/codespaces prebuild manifest --config-id $CONFIGURATION_ID --image-version Raw
            # Upload templates
            /.codespaces/agent/bin/codespaces prebuild upload --storage-type v2 --target-locations WestUs2 --repo-name ${{ github.repository }} --devcontainer-path $DEVCONTAINER_PATH --config-id $CONFIGURATION_ID --flush-only --image-version Raw
        - name: Save Creation Logs
          if: always()
          uses: actions/upload-artifact@v2
          with:
            name: logs
            path: "${{ env.LOG_PATH }}"
        env:
          CODESPACES_GITHUB__APITOKEN: "${{ secrets.GITHUB_TOKEN }}"
          CODESPACES_GITHUB__VSCSTARGET: production
          CODESPACES_GITHUB__WORKFLOWRUNID: "${{ github.run_id }}"
          CODESPACES_GITHUB__APIURLBASE: #{GitHub.api_url}
          CODESPACES_TELEMETRYSETTINGS__TELEMETRYENDPOINT: "${{ secrets.GITHUB_CODESPACES_INTERNAL_URL }}/${{ github.repository }}/agent/diagnostics"
          TARGET_VSCS_LOCATIONS: #{@region1}
          USER_SECRETS_JSON: "${{secrets.GITHUB_CODESPACE_AGENT_SECRETS}}"
          REPO_URL: "${{ github.server_url }}/${{ github.repository }}/tree/${{ github.ref_name }}"
          REPO_URL_WITHOUT_BRANCH: "${{ github.server_url }}/${{ github.repository }}"
          REPO_NAME_WITHOUT_OWNER: #{@repository.name}
          DEVCONTAINER_PATH: ".devcontainer/custom/devcontainer.json"
          CONFIGURATION_ID: #{@configuration.id}
          CODESPACES_GITHUB__VSCSTARGETURL: ''
          INTERNAL_URL: "${{ secrets.GITHUB_CODESPACES_INTERNAL_URL }}"
          LOG_PATH: "${{ secrets.GITHUB_CODESPACES_LOG_PATH}}"
          TARGET_KEY: "${{ secrets.GITHUB_CODESPACES_TARGET_KEY }}"
          TARGET_LOCATION_KEY: "${{ secrets.GITHUB_CODESPACES_LOCATION_KEY }}"
          TARGET_URL_KEY: "${{ secrets.GITHUB_CODESPACES_TARGET_URL_KEY }}"
    YAML

  end

  setup do
    GitHub.stubs(:actions_enabled?).returns(true)
    GitHub.stubs(:launch_github_app).returns(@actions_app)
    disable_feature_flag(:codespaces_custom_runner_label, @repository)
    disable_feature_flag(:codespaces_template_repo_prebuild_label, @repository)
    disable_feature_flag(:codespaces_storage_v2_prebuilds, @repository)
    disable_feature_flag(:codespaces_prebuilds_allow_token_write, @repository)
    disable_feature_flag(:codespaces_prebuilds_empty_permissions, @repository)
    disable_feature_flag(:codespaces_storage_v2_prebuilds_raw_only, @repository)
    disable_feature_flag(:codespaces_storage_v2_prebuilds_multi, @repository)
    disable_feature_flag(:codespaces_prebuilds_run_name, @repository)

    resp = GitHub::Launch::Services::Deploy::RunDynamicWorkflowResponse.new(execution_id: "123", workflow_run_id: 457)

    @run_dynamic_workflow_twirp_result = TwirpResponse.new(
      value: resp,
      status: 200,
      call_succeeded: true,
    )
  end

  def build_workflow_yaml_with_devcontainer_path(commit, prebuild_hash, repository, region, configuration, secret_value, host_name, api_url, graphql_api_url, image_allow_list_policy: "", feature_flags: "")
    vmagent_create_command = +"/.codespaces/agent/bin/codespaces prebuild create --repo-url $REPO_URL_WITHOUT_BRANCH --repo-name-no-owner $REPO_NAME_WITHOUT_OWNER --branch ${{ github.ref_name }} --devcontainer-path $DEVCONTAINER_PATH --commit ${{ github.sha }} --config-id $CONFIGURATION_ID --user-secrets-env USER_SECRETS_JSON"
    if image_allow_list_policy.present?
      vmagent_create_command << " --image-allow-list-env IMAGE_ALLOW_LIST_JSON"
    end
    if feature_flags.present?
      vmagent_create_command << " --features-env FEATURE_FLAGS_JSON"
    end
    if GitHub.flipper[:codespaces_larger_storage_size].enabled?(repository)
      vmagent_create_command << " --storage-size 256"
    end

    <<~YAML
      name: "[master]: #{commit.short_message_text}"
      'on': dynamic
      concurrency: #{prebuild_hash}-string
      defaults:
        run:
          shell: sudo -EH bash {0}
      jobs:
        prebuild:
          runs-on: codespaces-prebuild
          steps:
          - name: Mask secrets
            run: |
              echo -e $USER_SECRETS_JSON | jq 'del(.[] |
                select(.value=="#{secret_value}" or .value=="noreply@github.com" or .value=="https://#{host_name}" or .value=="#{api_url}" or .value=="#{graphql_api_url}" or .value=="#{repository.nwo}" or .value=="" or .value==null))' |
                jq 'unique_by(.value)' | jq .[] | jq '.value[]? // .value?' |jq -r \\\"::add-mask::\\\"+'.?'
          - name: Install Agent
            run: |
              umount -f /mnt
              set -exu pipefall
              # Download and extract agent
              mkdir -p /.codespaces/agent/bin
              cd /.codespaces/agent/bin
              FIRST_LOCATION=($TARGET_VSCS_LOCATIONS)
              AGENT_DOWNLOAD_URL="#{api_url}/$INTERNAL_URL/${{ github.repository }}/agent/download?$TARGET_LOCATION_KEY=$FIRST_LOCATION&workflow_run_id=$CODESPACES_GITHUB__WORKFLOWRUNID&$TARGET_KEY=$CODESPACES_GITHUB__VSCSTARGET&$TARGET_URL_KEY=${CODESPACES_GITHUB__VSCSTARGETURL-}"
              curl --location $AGENT_DOWNLOAD_URL \
                --header "Authorization: token $CODESPACES_GITHUB__APITOKEN" \
                --output tmp.zip
              unzip -q tmp.zip && rm tmp.zip
              # Install agent
              containerTmp=/mnt/containerTmp
              mkdir -p $containerTmp
              chmod o+rwt $containerTmp
              setfacl -dR -m o::rw $containerTmp
              codespacesSharedFolder=~/.codespaces/shared
              mkdir -p $codespacesSharedFolder
              chmod o+rw $codespacesSharedFolder
              setfacl -dR -m o::rw $codespacesSharedFolder
              chmod +x install_codespaces_agent.sh
              ./install_codespaces_agent.sh
              # Make copy of codespaces agent to mount
              mkdir -p /.codespaces/agent/mount
              cp -a /.codespaces/agent/bin/. /.codespaces/agent/mount
          - name: Create Template
            run: |
              # Create
              #{vmagent_create_command}
          - name: Upload Template
            run: |
              for location in $TARGET_VSCS_LOCATIONS; do
                /.codespaces/agent/bin/codespaces prebuild upload --location $location --repo-name ${{ github.repository }} --devcontainer-path $DEVCONTAINER_PATH --config-id $CONFIGURATION_ID
              done
          - name: Save Creation Logs
            if: always()
            uses: actions/upload-artifact@v2
            with:
              name: logs
              path: "${{ env.LOG_PATH }}"
          env:
            CODESPACES_GITHUB__APITOKEN: "${{ secrets.GITHUB_TOKEN }}"
            CODESPACES_GITHUB__VSCSTARGET: production
            CODESPACES_GITHUB__WORKFLOWRUNID: "${{ github.run_id }}"
            CODESPACES_GITHUB__APIURLBASE: #{api_url}
            CODESPACES_TELEMETRYSETTINGS__TELEMETRYENDPOINT: "${{ secrets.GITHUB_CODESPACES_INTERNAL_URL }}/${{ github.repository }}/agent/diagnostics"
            TARGET_VSCS_LOCATIONS: #{region}
            USER_SECRETS_JSON: "${{secrets.GITHUB_CODESPACE_AGENT_SECRETS}}"
            REPO_URL: "${{ github.server_url }}/${{ github.repository }}/tree/${{ github.ref_name }}"
            REPO_URL_WITHOUT_BRANCH: "${{ github.server_url }}/${{ github.repository }}"
            REPO_NAME_WITHOUT_OWNER: #{repository.name}
            DEVCONTAINER_PATH: ".devcontainer/custom/devcontainer.json"
            CONFIGURATION_ID: #{configuration.id}
            CODESPACES_GITHUB__VSCSTARGETURL: ''
            INTERNAL_URL: "${{ secrets.GITHUB_CODESPACES_INTERNAL_URL }}"
            LOG_PATH: "${{ secrets.GITHUB_CODESPACES_LOG_PATH}}"
            TARGET_KEY: "${{ secrets.GITHUB_CODESPACES_TARGET_KEY }}"
            TARGET_LOCATION_KEY: "${{ secrets.GITHUB_CODESPACES_LOCATION_KEY }}"
            TARGET_URL_KEY: "${{ secrets.GITHUB_CODESPACES_TARGET_URL_KEY }}"#{image_allow_list_policy}#{feature_flags}
    YAML
  end

  def build_workflow_yaml_without_devcontainer_path(commit, prebuild_hash, repository, region, configuration, secret_value, host_name, api_url, graphql_api_url)
    <<~YAML
      name: "[master]: #{commit.short_message_text}"
      'on': dynamic
      concurrency: #{prebuild_hash}-string
      defaults:
        run:
          shell: sudo -EH bash {0}
      jobs:
        prebuild:
          runs-on: codespaces-prebuild
          steps:
          - name: Mask secrets
            run: |
              echo -e $USER_SECRETS_JSON | jq 'del(.[] |
                select(.value=="#{secret_value}" or .value=="noreply@github.com" or .value=="https://#{host_name}" or .value=="#{api_url}" or .value=="#{graphql_api_url}" or .value=="#{repository.nwo}" or .value=="" or .value==null))' |
                jq 'unique_by(.value)' | jq .[] | jq '.value[]? // .value?' |jq -r \\\"::add-mask::\\\"+'.?'
          - name: Install Agent
            run: |
              umount -f /mnt
              set -exu pipefall
              # Download and extract agent
              mkdir -p /.codespaces/agent/bin
              cd /.codespaces/agent/bin
              FIRST_LOCATION=($TARGET_VSCS_LOCATIONS)
              AGENT_DOWNLOAD_URL="#{api_url}/$INTERNAL_URL/${{ github.repository }}/agent/download?$TARGET_LOCATION_KEY=$FIRST_LOCATION&workflow_run_id=$CODESPACES_GITHUB__WORKFLOWRUNID&$TARGET_KEY=$CODESPACES_GITHUB__VSCSTARGET&$TARGET_URL_KEY=${CODESPACES_GITHUB__VSCSTARGETURL-}"
              curl --location $AGENT_DOWNLOAD_URL \
                --header "Authorization: token $CODESPACES_GITHUB__APITOKEN" \
                --output tmp.zip
              unzip -q tmp.zip && rm tmp.zip
              # Install agent
              containerTmp=/mnt/containerTmp
              mkdir -p $containerTmp
              chmod o+rwt $containerTmp
              setfacl -dR -m o::rw $containerTmp
              codespacesSharedFolder=~/.codespaces/shared
              mkdir -p $codespacesSharedFolder
              chmod o+rw $codespacesSharedFolder
              setfacl -dR -m o::rw $codespacesSharedFolder
              chmod +x install_codespaces_agent.sh
              ./install_codespaces_agent.sh
              # Make copy of codespaces agent to mount
              mkdir -p /.codespaces/agent/mount
              cp -a /.codespaces/agent/bin/. /.codespaces/agent/mount
          - name: Create Template
            run: |
              # Create
              /.codespaces/agent/bin/codespaces prebuild create --repo-url $REPO_URL_WITHOUT_BRANCH --repo-name-no-owner $REPO_NAME_WITHOUT_OWNER --branch ${{ github.ref_name }} --commit ${{ github.sha }} --config-id $CONFIGURATION_ID --user-secrets-env USER_SECRETS_JSON
          - name: Upload Template
            run: |
              for location in $TARGET_VSCS_LOCATIONS; do
                /.codespaces/agent/bin/codespaces prebuild upload --location $location --repo-name ${{ github.repository }} --config-id $CONFIGURATION_ID
              done
          - name: Save Creation Logs
            if: always()
            uses: actions/upload-artifact@v2
            with:
              name: logs
              path: "${{ env.LOG_PATH }}"
          env:
            CODESPACES_GITHUB__APITOKEN: "${{ secrets.GITHUB_TOKEN }}"
            CODESPACES_GITHUB__VSCSTARGET: production
            CODESPACES_GITHUB__WORKFLOWRUNID: "${{ github.run_id }}"
            CODESPACES_GITHUB__APIURLBASE: #{api_url}
            CODESPACES_TELEMETRYSETTINGS__TELEMETRYENDPOINT: "${{ secrets.GITHUB_CODESPACES_INTERNAL_URL }}/${{ github.repository }}/agent/diagnostics"
            TARGET_VSCS_LOCATIONS: #{region}
            USER_SECRETS_JSON: "${{secrets.GITHUB_CODESPACE_AGENT_SECRETS}}"
            REPO_URL: "${{ github.server_url }}/${{ github.repository }}/tree/${{ github.ref_name }}"
            REPO_URL_WITHOUT_BRANCH: "${{ github.server_url }}/${{ github.repository }}"
            REPO_NAME_WITHOUT_OWNER: #{repository.name}
            DEVCONTAINER_PATH: ''
            CONFIGURATION_ID: #{configuration.id}
            CODESPACES_GITHUB__VSCSTARGETURL: ''
            INTERNAL_URL: "${{ secrets.GITHUB_CODESPACES_INTERNAL_URL }}"
            LOG_PATH: "${{ secrets.GITHUB_CODESPACES_LOG_PATH}}"
            TARGET_KEY: "${{ secrets.GITHUB_CODESPACES_TARGET_KEY }}"
            TARGET_LOCATION_KEY: "${{ secrets.GITHUB_CODESPACES_LOCATION_KEY }}"
            TARGET_URL_KEY: "${{ secrets.GITHUB_CODESPACES_TARGET_URL_KEY }}"
    YAML
  end

  context "multi tenant mode" do
    test "Workflow is valid yaml" do
      on_multi_tenant_enterprise(tenant: @business) do
        tenant_workflow_yaml = build_workflow_yaml_with_devcontainer_path(@tenant_commit, @tenant_prebuild_hash, @tenant_repository, @region1, @tenant_configuration, "GitHub", GitHub.host_name_with_tenant, GitHub.api_url, GitHub.graphql_api_url)
        assert YAML.parse(tenant_workflow_yaml)
      end
    end

    test "Workflow mask_secret_extended is valid yaml" do
      on_multi_tenant_enterprise(tenant: @business) do
        workflow = Codespaces::CreatePrebuildTemplateDynamicWorkflow.new(
          repository: @tenant_repository,
          branch: @tenant_branch,
          locations: [@region1],
          commit_sha: @tenant_commit_sha,
          concurrency_modifier: @concurrency_modifier)

        assert YAML.safe_load(workflow.dynamic_workflow_yaml)
      end
    end

    test "The devcontainer path and configuration id are sent in the workflow_yaml create template step" do
      on_multi_tenant_enterprise(tenant: @business) do
        tenant_workflow_yaml = build_workflow_yaml_with_devcontainer_path(@tenant_commit, @tenant_prebuild_hash, @tenant_repository, @region1, @tenant_configuration, "GitHub Enterprise", GitHub.host_name_with_tenant, GitHub.api_url, GitHub.graphql_api_url)

        command = Codespaces::CreatePrebuildTemplateDynamicWorkflow.new(
          repository: @tenant_repository,
          branch: @tenant_branch,
          locations: [@region1],
          concurrency_modifier: @concurrency_modifier,
          configuration: @tenant_configuration,
          devcontainer_path: @devcontainer_path
        )

        @tenant_repository.expects(:run_dynamic_workflow).with(
          actor: command.send(:codespaces_bot),
          workflow: tenant_workflow_yaml,
          inputs: nil,
          ref: @tenant_branch,
          workflow_name: Codespaces::Prebuilds.workflow_name(Codespaces::Vscs.default_target),
          slug: Codespaces::Prebuilds.workflow_slug(Codespaces::Vscs.default_target),
          integration_name: Apps::Privileged::Codespaces::PREBUILD_DYNAMIC_WORKFLOW_INTEGRATION_NAME,
          entry_point: :codespaces_commands_create_prebuild_template_dynamic_workflow
        ).returns(
          @run_dynamic_workflow_twirp_result
        )

        result = command.perform
        assert_equal @run_dynamic_workflow_twirp_result, result
      end
    end

    test "When there is no devcontainer path then it is not sent in request" do
      on_multi_tenant_enterprise(tenant: @business) do
        tenant_workflow_yaml = build_workflow_yaml_without_devcontainer_path(@tenant_commit, @tenant_prebuild_hash_no_devcontainer, @tenant_repository, @region1, @tenant_configuration, "GitHub Enterprise", GitHub.host_name_with_tenant, GitHub.api_url, GitHub.graphql_api_url)

        expected_yaml = YAML.safe_load(tenant_workflow_yaml)

        workflow = Codespaces::CreatePrebuildTemplateDynamicWorkflow.new(
          repository: @tenant_repository,
          branch: @tenant_branch,
          locations: [@region1],
          commit_sha: @tenant_commit_sha,
          concurrency_modifier: @concurrency_modifier,
          configuration: @tenant_configuration)

        result_yaml = YAML.safe_load(workflow.dynamic_workflow_yaml)

        # verify dynamic workflow yaml created matches expected yaml
        assert_equal expected_yaml, result_yaml
        @tenant_repository.expects(:run_dynamic_workflow).returns(
          @run_dynamic_workflow_twirp_result
        )

        result = Codespaces::CreatePrebuildTemplateDynamicWorkflow.call(
          repository: @tenant_repository,
          branch: @tenant_branch,
          locations: [@region1],
          concurrency_modifier: @concurrency_modifier,
          configuration: @tenant_configuration,
        )

        assert_equal @run_dynamic_workflow_twirp_result, result
      end
    end
  end

  test "Workflow mask_secret_extended is valid yaml" do
    workflow = Codespaces::CreatePrebuildTemplateDynamicWorkflow.new(
      repository: @repository,
      branch: @branch,
      locations: [@region1],
      commit_sha: @commit_sha,
      concurrency_modifier: @concurrency_modifier)

    assert YAML.safe_load(workflow.dynamic_workflow_yaml)
  end

  test "with a runner group configured" do
    enable_feature_flag(:codespaces_prebuild_runner_choice, @repository)
    @tenant_configuration.runner_group = "org/Default"
    @tenant_configuration.runner_label = "custom-codespaces-runner"

    workflow = Codespaces::CreatePrebuildTemplateDynamicWorkflow.new(
      repository: @repository,
      branch: @branch,
      locations: [@region1],
      commit_sha: @commit_sha,
      concurrency_modifier: @concurrency_modifier,
      configuration: @tenant_configuration)

    result_yaml = YAML.safe_load(workflow.dynamic_workflow_yaml)
    assert_equal({ "group" => "org/Default", "label" => "custom-codespaces-runner" }, result_yaml.dig("jobs", "prebuild", "runs-on"))
  end

  context "CreatePrebuildTemplateDynamicWorkflow" do
    test "Workflow is valid yaml" do
      assert YAML.safe_load(@workflow_yaml)
      # Check that the values in env are one of: string, number, boolean
      loaded_yaml = YAML.safe_load(@workflow_yaml)
      yaml_env = loaded_yaml["jobs"]["prebuild"]["env"]
      yaml_env.each do |key, value|
        t = value.class
        if t == String || t == Integer || t == TrueClass || t == FalseClass
          # pass
        else
          # Fail test
          fail "Unsupported type '#{t}' for value of environment variable '#{key}'"
        end
      end
    end

    test "Workflow is valid yaml for storage v2" do
      assert YAML.safe_load(@workflow_yaml_storage_v2)
      # Check that the values in env are one of: string, number, boolean
      loaded_yaml = YAML.safe_load(@workflow_yaml_storage_v2)
      yaml_env = loaded_yaml["jobs"]["prebuild"]["env"]
      yaml_env.each do |key, value|
        t = value.class
        if t == String || t == Integer || t == TrueClass || t == FalseClass
          # pass
        else
          # Fail test
          fail "Unsupported type '#{t}' for value of environment variable '#{key}'"
        end
      end
    end

    test "Workflow is valid yaml for storage v2 without devcontainer" do
      assert YAML.safe_load(@workflow_yaml_storage_v2_no_devcontainer_path)
      # Check that the values in env are one of: string, number, boolean
      loaded_yaml = YAML.safe_load(@workflow_yaml_storage_v2_no_devcontainer_path)
      yaml_env = loaded_yaml["jobs"]["prebuild"]["env"]
      yaml_env.each do |key, value|
        t = value.class
        if t == String || t == Integer || t == TrueClass || t == FalseClass
          # pass
        else
          # Fail test
          fail "Unsupported type '#{t}' for value of environment variable '#{key}'"
        end
      end
    end

    test "Workflow is valid yaml for storage v2 with multi versions" do
      assert YAML.safe_load(@workflow_yaml_storage_v2_multi_versions)
      # Check that the values in env are one of: string, number, boolean
      loaded_yaml = YAML.safe_load(@workflow_yaml_storage_v2_multi_versions)
      yaml_env = loaded_yaml["jobs"]["prebuild"]["env"]
      yaml_env.each do |key, value|
        t = value.class
        if t == String || t == Integer || t == TrueClass || t == FalseClass
          # pass
        else
          # Fail test
          fail "Unsupported type '#{t}' for value of environment variable '#{key}'"
        end
      end
    end

    test "Workflow is valid yaml for storage v2 with raw only" do
      assert YAML.safe_load(@workflow_yaml_storage_v2_raw_only)
      # Check that the values in env are one of: string, number, boolean
      loaded_yaml = YAML.safe_load(@workflow_yaml_storage_v2_raw_only)
      yaml_env = loaded_yaml["jobs"]["prebuild"]["env"]
      yaml_env.each do |key, value|
        t = value.class
        if t == String || t == Integer || t == TrueClass || t == FalseClass
          # pass
        else
          # Fail test
          fail "Unsupported type '#{t}' for value of environment variable '#{key}'"
        end
      end
    end

    test "Workflow is valid yaml without artifacts" do
      assert YAML.safe_load(@workflow_yaml_no_artifacts)
      loaded_yaml = YAML.safe_load(@workflow_yaml_no_artifacts)
      # Check that the values in env are one of: string, number, boolean
      yaml_env = loaded_yaml["jobs"]["prebuild"]["env"]
      yaml_env.each do |key, value|
        t = value.class
        if t == String || t == Integer || t == TrueClass || t == FalseClass
          # pass
        else
          # Fail test
          fail "Unsupported type '#{t}' for value of environment variable '#{key}'"
        end
      end
    end

    test "Uses most recent commit if none passed" do
      expected_yaml = YAML.safe_load(@workflow_yaml)

      workflow = Codespaces::CreatePrebuildTemplateDynamicWorkflow.new(
        repository: @repository,
        branch: @branch,
        locations: [@region1],
        commit_sha: @commit_sha,
        concurrency_modifier: @concurrency_modifier,
        configuration: @configuration,
        devcontainer_path: @devcontainer_path)

      result_yaml = YAML.safe_load(workflow.dynamic_workflow_yaml)

      # verify dynamic workflow yaml created matches expected yaml
      assert_equal expected_yaml, result_yaml

      @repository.expects(:run_dynamic_workflow).returns(
        @run_dynamic_workflow_twirp_result
      )

      result = Codespaces::CreatePrebuildTemplateDynamicWorkflow.call(
        repository: @repository,
        branch: @branch,
        locations: [@region1],
        concurrency_modifier: @concurrency_modifier,
        configuration: @configuration
      )

      assert_equal @run_dynamic_workflow_twirp_result, result
    end

    test "The devcontainer path and configuration id are sent in the workflow_yaml create template step" do
      @repository.expects(:run_dynamic_workflow).with(
        actor: @codespaces_bot,
        workflow: @workflow_yaml,
        inputs: nil,
        ref: @branch,
        workflow_name: Codespaces::Prebuilds.workflow_name(Codespaces::Vscs.default_target),
        slug: Codespaces::Prebuilds.workflow_slug(Codespaces::Vscs.default_target),
        integration_name: Apps::Privileged::Codespaces::PREBUILD_DYNAMIC_WORKFLOW_INTEGRATION_NAME,
        entry_point: :codespaces_commands_create_prebuild_template_dynamic_workflow
      ).returns(
        @run_dynamic_workflow_twirp_result
      )

      result = Codespaces::CreatePrebuildTemplateDynamicWorkflow.call(
        repository: @repository,
        branch: @branch,
        locations: [@region1],
        concurrency_modifier: @concurrency_modifier,
        configuration: @configuration,
        devcontainer_path: @devcontainer_path
      )
      assert_equal @run_dynamic_workflow_twirp_result, result
    end

    test "Set permissions correctly when the empty permissions flag is on" do
      enable_feature_flag(:codespaces_prebuilds_empty_permissions, @repository)

      workflow = Codespaces::CreatePrebuildTemplateDynamicWorkflow.new(
        repository: @repository,
        branch: @branch,
        locations: [@region1],
        commit_sha: @commit_sha,
        concurrency_modifier: @concurrency_modifier,
        configuration: @configuration)

      result_yaml = YAML.safe_load(workflow.dynamic_workflow_yaml)

      expected_permissions = YAML.safe_load("{}")

      assert_equal expected_permissions, result_yaml.dig("jobs", "prebuild", "permissions")
    end

    test "Set permissions correctly when the allow token feature is set" do
      enable_feature_flag(:codespaces_prebuilds_allow_token_write, @repository)

      workflow = Codespaces::CreatePrebuildTemplateDynamicWorkflow.new(
        repository: @repository,
        branch: @branch,
        locations: [@region1],
        commit_sha: @commit_sha,
        concurrency_modifier: @concurrency_modifier,
        configuration: @configuration)

      result_yaml = YAML.safe_load(workflow.dynamic_workflow_yaml)

      expected_permissions = YAML.safe_load("
        contents: read
        id-token: write")

      assert_equal expected_permissions, result_yaml.dig("jobs", "prebuild", "permissions")
    end

    test "Set permissions correctly when the allow token feature is set for enterprise" do
      enterprise = create :business
      enterprise.add_organization(@org)
      enable_feature_flag(:codespaces_prebuilds_allow_token_write, enterprise)

      workflow = Codespaces::CreatePrebuildTemplateDynamicWorkflow.new(
        repository: @repository,
        branch: @branch,
        locations: [@region1],
        commit_sha: @commit_sha,
        concurrency_modifier: @concurrency_modifier,
        configuration: @configuration)

      result_yaml = YAML.safe_load(workflow.dynamic_workflow_yaml)

      expected_permissions = YAML.safe_load("
        contents: read
        id-token: write")

      assert_equal expected_permissions, result_yaml.dig("jobs", "prebuild", "permissions")
    end

    test "Set permissions correctly when the allow token feature is set for org" do
      enable_feature_flag(:codespaces_prebuilds_allow_token_write, @org)

      workflow = Codespaces::CreatePrebuildTemplateDynamicWorkflow.new(
        repository: @repository,
        branch: @branch,
        locations: [@region1],
        commit_sha: @commit_sha,
        concurrency_modifier: @concurrency_modifier,
        configuration: @configuration)

      result_yaml = YAML.safe_load(workflow.dynamic_workflow_yaml)

      expected_permissions = YAML.safe_load("
        contents: read
        id-token: write")

      assert_equal expected_permissions, result_yaml.dig("jobs", "prebuild", "permissions")
    end

    test "Generate template job successfully when allow token write feature is set" do
      enable_feature_flag(:codespaces_prebuilds_allow_token_write, @repository)

      workflow = Codespaces::CreatePrebuildTemplateDynamicWorkflow.new(
        repository: @repository,
        branch: @branch,
        locations: [@region1],
        commit_sha: @commit_sha,
        concurrency_modifier: @concurrency_modifier,
        configuration: @configuration)

      result_yaml = YAML.safe_load(workflow.dynamic_workflow_yaml)

      expected_template_job = YAML.safe_load("name: Create Template
run: |
  # Merge token secrets
  export USER_SECRETS_JSON=$(echo -e $USER_SECRETS_JSON | jq --arg url \"$ACTIONS_ID_TOKEN_REQUEST_URL\" --arg token \"$ACTIONS_ID_TOKEN_REQUEST_TOKEN\" '. + [{\"type\": \"EnvironmentVariable\", \"name\": \"ACTIONS_ID_TOKEN_REQUEST_URL\", \"value\": $url}, {\"type\": \"EnvironmentVariable\", \"name\": \"ACTIONS_ID_TOKEN_REQUEST_TOKEN\", \"value\": $token}]')
  # Create
  /.codespaces/agent/bin/codespaces prebuild create --repo-url $REPO_URL_WITHOUT_BRANCH --repo-name-no-owner $REPO_NAME_WITHOUT_OWNER --branch ${{ github.ref_name }} --commit ${{ github.sha }} --config-id $CONFIGURATION_ID --user-secrets-env USER_SECRETS_JSON
")

      actual_jobs = result_yaml.dig("jobs", "prebuild", "steps")

      # Verify we have a step called "Create Template"
      create = actual_jobs.find { |step| step["name"] == "Create Template" }

      assert_equal expected_template_job, create
    end

    test "When there is no devcontainer path then it is not sent in request" do
      expected_yaml = YAML.safe_load(@workflow_yaml_no_devcontainer_path)

      workflow = Codespaces::CreatePrebuildTemplateDynamicWorkflow.new(
        repository: @repository,
        branch: @branch,
        locations: [@region1],
        commit_sha: @commit_sha,
        concurrency_modifier: @concurrency_modifier,
        configuration: @configuration)

      result_yaml = YAML.safe_load(workflow.dynamic_workflow_yaml)

      # verify dynamic workflow yaml created matches expected yaml
      assert_equal expected_yaml, result_yaml

      @repository.expects(:run_dynamic_workflow).returns(
        @run_dynamic_workflow_twirp_result
      )

      result = Codespaces::CreatePrebuildTemplateDynamicWorkflow.call(
        repository: @repository,
        branch: @branch,
        locations: [@region1],
        concurrency_modifier: @concurrency_modifier,
        configuration: @configuration,
      )
      assert_equal @run_dynamic_workflow_twirp_result, result
    end

    test "When storage v2 mode is enabled it sends the correct commands" do
      enable_feature_flag(:codespaces_storage_v2_prebuilds, @repository)
      disable_feature_flag(:codespaces_storage_v2_prebuilds_raw_only, @repository)
      disable_feature_flag(:codespaces_storage_v2_prebuilds_multi, @repository)

      expected_yaml = YAML.safe_load(@workflow_yaml_storage_v2)

      workflow = Codespaces::CreatePrebuildTemplateDynamicWorkflow.new(
        repository: @repository,
        branch: @branch,
        locations: [@region1],
        commit_sha: @commit_sha,
        concurrency_modifier: @concurrency_modifier,
        configuration: @configuration,
        devcontainer_path: @devcontainer_path)

      result_yaml = YAML.safe_load(workflow.dynamic_workflow_yaml)

      # verify dynamic workflow yaml created matches expected yaml
      assert_equal expected_yaml, result_yaml
      @repository.expects(:run_dynamic_workflow).returns(
        @run_dynamic_workflow_twirp_result
      )

      result = Codespaces::CreatePrebuildTemplateDynamicWorkflow.call(
        repository: @repository,
        branch: @branch,
        locations: [@region1],
        concurrency_modifier: @concurrency_modifier,
        configuration: @configuration,
      )
      assert_equal @run_dynamic_workflow_twirp_result, result
    end

    test "When storage v2 mode is enabled on the repos owner it sends the correct commands" do
      enable_feature_flag(:codespaces_storage_v2_prebuilds, @org)
      disable_feature_flag(:codespaces_storage_v2_prebuilds_raw_only, @repository)
      disable_feature_flag(:codespaces_storage_v2_prebuilds_multi, @repository)

      expected_yaml = YAML.safe_load(@workflow_yaml_storage_v2)

      workflow = Codespaces::CreatePrebuildTemplateDynamicWorkflow.new(
        repository: @repository,
        branch: @branch,
        locations: [@region1],
        commit_sha: @commit_sha,
        concurrency_modifier: @concurrency_modifier,
        configuration: @configuration,
        devcontainer_path: @devcontainer_path)

      expected = workflow.use_storage_v2
      assert_equal true, expected

      result_yaml = YAML.safe_load(workflow.dynamic_workflow_yaml)

      # verify dynamic workflow yaml created matches expected yaml
      assert_equal expected_yaml, result_yaml
      @repository.expects(:run_dynamic_workflow).returns(
        @run_dynamic_workflow_twirp_result
      )

      result = Codespaces::CreatePrebuildTemplateDynamicWorkflow.call(
        repository: @repository,
        branch: @branch,
        locations: [@region1],
        concurrency_modifier: @concurrency_modifier,
        configuration: @configuration,
      )
      assert_equal @run_dynamic_workflow_twirp_result, result
    end

    test "When storage v2 mode is enabled on the repos owner and multi image versions are enabled it sends the correct commands" do
      enable_feature_flag(:codespaces_storage_v2_prebuilds, @org)
      enable_feature_flag(:codespaces_storage_v2_prebuilds_multi, @repository)

      expected_yaml = YAML.safe_load(@workflow_yaml_storage_v2_multi_versions)

      workflow = Codespaces::CreatePrebuildTemplateDynamicWorkflow.new(
        repository: @repository,
        branch: @branch,
        locations: [@region1],
        commit_sha: @commit_sha,
        concurrency_modifier: @concurrency_modifier,
        configuration: @configuration,
        devcontainer_path: @devcontainer_path)

      expected = workflow.use_storage_v2
      assert_equal true, expected

      result_yaml = YAML.safe_load(workflow.dynamic_workflow_yaml)

      # verify dynamic workflow yaml created matches expected yaml
      assert_equal expected_yaml, result_yaml
      @repository.expects(:run_dynamic_workflow).returns(
        @run_dynamic_workflow_twirp_result
      )

      result = Codespaces::CreatePrebuildTemplateDynamicWorkflow.call(
        repository: @repository,
        branch: @branch,
        locations: [@region1],
        concurrency_modifier: @concurrency_modifier,
        configuration: @configuration,
      )
      assert_equal @run_dynamic_workflow_twirp_result, result
    end

    test "When storage v2 mode is enabled on the repos owner and only raw version image is enabled it sends the correct commands" do
      enable_feature_flag(:codespaces_storage_v2_prebuilds, @org)
      enable_feature_flag(:codespaces_storage_v2_prebuilds_raw_only, @repository)
      disable_feature_flag(:codespaces_storage_v2_prebuilds_multi, @repository)

      expected_yaml = YAML.safe_load(@workflow_yaml_storage_v2_raw_only)

      workflow = Codespaces::CreatePrebuildTemplateDynamicWorkflow.new(
        repository: @repository,
        branch: @branch,
        locations: [@region1],
        commit_sha: @commit_sha,
        concurrency_modifier: @concurrency_modifier,
        configuration: @configuration,
        devcontainer_path: @devcontainer_path)

      expected = workflow.use_storage_v2
      assert_equal true, expected

      result_yaml = YAML.safe_load(workflow.dynamic_workflow_yaml)

      # verify dynamic workflow yaml created matches expected yaml
      assert_equal expected_yaml, result_yaml
      @repository.expects(:run_dynamic_workflow).returns(
        @run_dynamic_workflow_twirp_result
      )

      result = Codespaces::CreatePrebuildTemplateDynamicWorkflow.call(
        repository: @repository,
        branch: @branch,
        locations: [@region1],
        concurrency_modifier: @concurrency_modifier,
        configuration: @configuration,
      )
      assert_equal @run_dynamic_workflow_twirp_result, result
    end

    test "When storage v2 mode is enabled for a pre-production vscs target it does not use storage v2 for production" do
      enable_feature_flag(:codespaces_storage_v2_prebuilds_ppe, @repository)
      disable_feature_flag(:codespaces_storage_v2_prebuilds)
      disable_feature_flag(:codespaces_storage_v2_prebuilds_raw_only_ppe, @repository)
      disable_feature_flag(:codespaces_storage_v2_prebuilds_multi_ppe, @repository)

      storage_v2_yaml = YAML.safe_load(@workflow_yaml_storage_v2)

      workflow = Codespaces::CreatePrebuildTemplateDynamicWorkflow.new(
        repository: @repository,
        branch: @branch,
        locations: [@region1],
        commit_sha: @commit_sha,
        concurrency_modifier: @concurrency_modifier,
        configuration: @configuration,
        devcontainer_path: @devcontainer_path)

      result_yaml = YAML.safe_load(workflow.dynamic_workflow_yaml)

      # verify dynamic workflow yaml is not storage v2 yaml
      refute_equal storage_v2_yaml, result_yaml
      @repository.expects(:run_dynamic_workflow).returns(
        @run_dynamic_workflow_twirp_result
      )

      result = Codespaces::CreatePrebuildTemplateDynamicWorkflow.call(
        repository: @repository,
        branch: @branch,
        locations: [@region1],
        concurrency_modifier: @concurrency_modifier,
        configuration: @configuration,
      )
      assert_equal @run_dynamic_workflow_twirp_result, result
    end

    test "When there is no devcontainer path in storage v2 mode then it is not sent in request" do
      enable_feature_flag(:codespaces_storage_v2_prebuilds, @repository)
      disable_feature_flag(:codespaces_storage_v2_prebuilds_raw_only, @repository)
      disable_feature_flag(:codespaces_storage_v2_prebuilds_multi, @repository)

      expected_yaml = YAML.safe_load(@workflow_yaml_storage_v2_no_devcontainer_path)

      workflow = Codespaces::CreatePrebuildTemplateDynamicWorkflow.new(
        repository: @repository,
        branch: @branch,
        locations: [@region1],
        commit_sha: @commit_sha,
        concurrency_modifier: @concurrency_modifier,
        configuration: @configuration)

      result_yaml = YAML.safe_load(workflow.dynamic_workflow_yaml)

      # verify dynamic workflow yaml created matches expected yaml
      assert_equal expected_yaml, result_yaml
      @repository.expects(:run_dynamic_workflow).returns(
        @run_dynamic_workflow_twirp_result
      )

      result = Codespaces::CreatePrebuildTemplateDynamicWorkflow.call(
        repository: @repository,
        branch: @branch,
        locations: [@region1],
        concurrency_modifier: @concurrency_modifier,
        configuration: @configuration,
      )
      assert_equal @run_dynamic_workflow_twirp_result, result
    end

    test "creates dynamic workflow without artifacts step when feature flag is enabled" do
      enable_feature_flag(:codespaces_remove_prebuild_artifacts, @repository)

      expected_yaml = YAML.safe_load(@workflow_yaml_no_artifacts)

      workflow = Codespaces::CreatePrebuildTemplateDynamicWorkflow.new(
        repository: @repository,
        branch: @branch,
        locations: [@region1],
        commit_sha: @commit_sha,
        concurrency_modifier: @concurrency_modifier,
        configuration: @configuration,
        devcontainer_path: @devcontainer_path)

      result_yaml = YAML.safe_load(workflow.dynamic_workflow_yaml)

      # verify dynamic workflow yaml created matches expected yaml
      assert_equal expected_yaml, result_yaml

      @repository.expects(:run_dynamic_workflow).returns(
        @run_dynamic_workflow_twirp_result
      )

      result = Codespaces::CreatePrebuildTemplateDynamicWorkflow.call(
        repository: @repository,
        branch: @branch,
        locations: [@region1],
        concurrency_modifier: @concurrency_modifier,
        configuration: @configuration,
      )
      assert_equal @run_dynamic_workflow_twirp_result, result
    end

    test "fails with non local vscs_target and url" do
      @repository.expects(:run_dynamic_workflow).never
      enable_feature_flag(:codespaces_developer)

      assert_raises Codespaces::CreatePrebuildTemplateDynamicWorkflow::InvalidVSCSTargetAndUrlError do
        Codespaces::CreatePrebuildTemplateDynamicWorkflow.call(
          repository: @repository,
          branch: @branch,
          locations: [@region1],
          vscs_target: :ppe,
          vscs_target_url: "awesome.wow",
          commit_sha: @commit_sha,
          concurrency_modifier: @concurrency_modifier,
        )
      end
    end

    test "fails if the repository has a non production target and isn't a codespaces developer" do
      disable_feature_flag(:codespaces_developer)
      assert_raises_with_message Codespaces::ValidatePrebuildAccess::AuthorizationError, "vscs_target specified but the repository owner does not have access to developer features" do
        Codespaces::CreatePrebuildTemplateDynamicWorkflow.call(
          repository: @repository,
          branch: @branch,
          locations: [@region1],
          vscs_target: :ppe,
          commit_sha: @commit_sha,
          concurrency_modifier: @concurrency_modifier,
        )
      end
    end

    test "fails with an invalid region" do
      @repository.expects(:run_dynamic_workflow).never

      assert_raises Codespaces::CreatePrebuildTemplateDynamicWorkflow::InvalidRegionError do
        Codespaces::CreatePrebuildTemplateDynamicWorkflow.call(
          repository: @repository,
          branch: @branch,
          locations: ["invalidRegion"],
          commit_sha: @commit_sha,
          concurrency_modifier: @concurrency_modifier,
        )
      end
    end

    test "fails with invalid commit_sha" do
      @repository.expects(:run_dynamic_workflow).never

      assert_raises RepositoryObjectsCollection::InvalidObjectId do
        Codespaces::CreatePrebuildTemplateDynamicWorkflow.call(
          repository: @repository,
          branch: @branch,
          locations: [@region1],
          concurrency_modifier: @concurrency_modifier,
          commit_sha: "1234",
        )
      end
    end

    test "fails if branch isn't found for repo" do
      @repository.expects(:run_dynamic_workflow).never

      assert_raises Codespaces::CreatePrebuildTemplateDynamicWorkflow::InvalidBranchError do
        Codespaces::CreatePrebuildTemplateDynamicWorkflow.call(
          repository: @repository,
          branch: "banana",
          locations: [@region1],
          commit_sha: @commit_sha,
          concurrency_modifier: @concurrency_modifier,
        )
      end
    end

    test "fail if codespaces enabled isn't enabled" do
      GitHub.stubs(:codespaces_enabled?).returns(false)
      @repository.expects(:run_dynamic_workflow).never

      assert_raises_with_message Codespaces::CreatePrebuildTemplateDynamicWorkflow::AuthorizationError, "this repository does not support this feature" do
        Codespaces::CreatePrebuildTemplateDynamicWorkflow.call(
          repository: @repository,
          branch: @branch,
          locations: [@region1],
          commit_sha: @commit_sha,
          concurrency_modifier: @concurrency_modifier,
        )
      end
    end

    test "handles external service failure by logging to failbot" do
      Failbot.expects(:report).with(instance_of(TwirpHelper::TwirpError), { app: "github-launch" })
      Failbot.expects(:report).with(instance_of(Codespaces::CreatePrebuildTemplateDynamicWorkflow::RunDynamicWorkflowError))
      Codespaces::CreatePrebuildTemplateDynamicWorkflow.call(
        repository: @repository,
        branch: @branch,
        locations: [@region1],
        commit_sha: @commit_sha,
        concurrency_modifier: @concurrency_modifier,
      )
    end

    test "runs with new region if all regions flag is enabled" do
      enable_feature_flag(:codespaces_prebuilds_new_regions, @repository)

      @repository.expects(:run_dynamic_workflow).once

      Codespaces::CreatePrebuildTemplateDynamicWorkflow.call(
        repository: @repository,
        branch: @branch,
        locations: %w[UkSouth EastUs],
        commit_sha: @commit_sha,
        concurrency_modifier: @concurrency_modifier,
      )
    end

    test "runs with new region" do
      @repository.expects(:run_dynamic_workflow).once

      Codespaces::CreatePrebuildTemplateDynamicWorkflow.call(
        repository: @repository,
        branch: @branch,
        locations: %w[UkSouth EastUs],
        commit_sha: @commit_sha,
        concurrency_modifier: @concurrency_modifier,
      )
    end

    test "Runs dynamic workflow with masked step extended when feature flag is enabled" do
      workflow_with_secret_extended = Codespaces::CreatePrebuildTemplateDynamicWorkflow.new(
        repository: @repository,
        branch: @branch,
        locations: [@region1],
        commit_sha: @commit_sha,
        concurrency_modifier: @concurrency_modifier)

      workflow_yaml_with_mask_secret_extended = workflow_with_secret_extended.dynamic_workflow_yaml
      @repository.expects(:run_dynamic_workflow).with(
        actor: @codespaces_bot,
        workflow: workflow_yaml_with_mask_secret_extended,
        inputs: nil,
        ref: @branch,
        workflow_name: Codespaces::Prebuilds.workflow_name(Codespaces::Vscs.default_target),
        slug: Codespaces::Prebuilds.workflow_slug(Codespaces::Vscs.default_target),
        integration_name: Apps::Privileged::Codespaces::PREBUILD_DYNAMIC_WORKFLOW_INTEGRATION_NAME,
        entry_point: :codespaces_commands_create_prebuild_template_dynamic_workflow
      ).returns(
        @run_dynamic_workflow_twirp_result
      )

      result = Codespaces::CreatePrebuildTemplateDynamicWorkflow.call(
        repository: @repository,
        branch: @branch,
        locations: [@region1],
        commit_sha: @commit_sha,
        concurrency_modifier: @concurrency_modifier,
      )
      assert_equal @run_dynamic_workflow_twirp_result, result
    end

    test "Set run-name when devcontainer set and feature enabled" do
      enable_feature_flag(:codespaces_prebuilds_run_name, @repository)

      workflow = Codespaces::CreatePrebuildTemplateDynamicWorkflow.new(
        repository: @repository,
        branch: @branch,
        locations: [@region1],
        commit_sha: @commit_sha,
        concurrency_modifier: @concurrency_modifier,
        devcontainer_path: @devcontainer_path,
        configuration: @configuration)


      result_yaml = YAML.safe_load(workflow.dynamic_workflow_yaml)

      refute_empty @devcontainer_path
      assert_equal @devcontainer_path, result_yaml["run-name"]
    end

    test "Does not set run-name when devcontainer is nil and feature enabled" do
      enable_feature_flag(:codespaces_prebuilds_run_name, @repository)

      workflow = Codespaces::CreatePrebuildTemplateDynamicWorkflow.new(
        repository: @repository,
        branch: @branch,
        locations: [@region1],
        commit_sha: @commit_sha,
        concurrency_modifier: @concurrency_modifier,
        devcontainer_path: nil,
        configuration: @configuration)


      result_yaml = YAML.safe_load(workflow.dynamic_workflow_yaml)

      assert_nil result_yaml["run-name"]
    end

    context "emits logs" do
      context "for storage v1" do
        test "when kicking off dynamic workflow" do
          expected_keys = {
            "gh.repo.id" => @repository.id,
            "gh.codespaces.prebuilds.configuration.id" => @configuration.id,
            "gh.codespaces.regions" => @region1,
            "gh.codespaces.vscs_target" => :production,
            "gh.codespaces.use_storage_v2" => false,
            "code.namespace" => "Codespaces::CreatePrebuildTemplateDynamicWorkflow",
          }

          assert_logged(Body: "Kicking off Codespaces Prebuild Create Template Dynamic Workflow", **expected_keys) do
            @repository.expects(:run_dynamic_workflow).returns(
              @run_dynamic_workflow_twirp_result)

            Codespaces::CreatePrebuildTemplateDynamicWorkflow.call(
              repository: @repository,
              branch: @branch,
              locations: [@region1],
              commit_sha: @commit_sha,
              concurrency_modifier: @concurrency_modifier,
              devcontainer_path: @devcontainer_path,
              configuration: @configuration,
            )
          end
        end
        test "when dynamic workflow is successful" do
          expected_keys = {
            "gh.repo.id" => @repository.id,
            "gh.repo.owner.login" => @repository.owner.display_login,
            "gh.codespaces.prebuilds.configuration.id" => @configuration.id,
            "gh.codespaces.prebuild_hash" => @prebuild_hash,
            "gh.codespaces.regions" => @region1,
            "gh.codespaces.prebuild.workflow_run_id" => @run_dynamic_workflow_twirp_result.value.workflow_run_id,
            "gh.codespaces.vscs_target" => :production,
            "gh.codespaces.use_storage_v2" => false,
            "code.namespace" => "Codespaces::CreatePrebuildTemplateDynamicWorkflow",
          }

          assert_logged(Body: "Codespaces Prebuild Create Template Dynamic Workflow successfully kicked off", **expected_keys) do
            @repository.expects(:run_dynamic_workflow).returns(
              @run_dynamic_workflow_twirp_result)

            Codespaces::CreatePrebuildTemplateDynamicWorkflow.call(
              repository: @repository,
              branch: @branch,
              locations: [@region1],
              commit_sha: @commit_sha,
              concurrency_modifier: @concurrency_modifier,
              devcontainer_path: @devcontainer_path,
              configuration: @configuration,
            )
          end
        end
      end

      context "for storage v2" do
        test "when kicking off dynamic workflow" do
          enable_feature_flag(:codespaces_storage_v2_prebuilds, @repository)
          disable_feature_flag(:codespaces_storage_v2_prebuilds_raw_only, @repository)
          disable_feature_flag(:codespaces_storage_v2_prebuilds_multi, @repository)

          expected_keys = {
            "gh.repo.id" => @repository.id,
            "gh.codespaces.prebuilds.configuration.id" => @configuration.id,
            "gh.codespaces.regions" => @region1,
            "gh.codespaces.vscs_target" => :production,
            "gh.codespaces.use_storage_v2" => true,
            "code.namespace" => "Codespaces::CreatePrebuildTemplateDynamicWorkflow",
          }

          assert_logged(Body: "Kicking off Codespaces Prebuild Create Template Dynamic Workflow", **expected_keys) do
            @repository.expects(:run_dynamic_workflow).returns(
              @run_dynamic_workflow_twirp_result)

            Codespaces::CreatePrebuildTemplateDynamicWorkflow.call(
              repository: @repository,
              branch: @branch,
              locations: [@region1],
              commit_sha: @commit_sha,
              concurrency_modifier: @concurrency_modifier,
              devcontainer_path: @devcontainer_path,
              configuration: @configuration,
            )
          end
        end
        test "when dynamic workflow is successful" do
          enable_feature_flag(:codespaces_storage_v2_prebuilds, @repository)
          disable_feature_flag(:codespaces_storage_v2_prebuilds_raw_only, @repository)
          disable_feature_flag(:codespaces_storage_v2_prebuilds_multi, @repository)

          expected_keys = {
            "gh.repo.id" => @repository.id,
            "gh.repo.owner.login" => @repository.owner.display_login,
            "gh.codespaces.prebuilds.configuration.id" => @configuration.id,
            "gh.codespaces.prebuild_hash" => @prebuild_hash,
            "gh.codespaces.regions" => @region1,
            "gh.codespaces.prebuild.workflow_run_id" => @run_dynamic_workflow_twirp_result.value.workflow_run_id,
            "gh.codespaces.vscs_target" => :production,
            "gh.codespaces.use_storage_v2" => true,
            "code.namespace" => "Codespaces::CreatePrebuildTemplateDynamicWorkflow",
          }

          assert_logged(Body: "Codespaces Prebuild Create Template Dynamic Workflow successfully kicked off", **expected_keys) do
            @repository.expects(:run_dynamic_workflow).returns(
              @run_dynamic_workflow_twirp_result)

            Codespaces::CreatePrebuildTemplateDynamicWorkflow.call(
              repository: @repository,
              branch: @branch,
              locations: [@region1],
              commit_sha: @commit_sha,
              concurrency_modifier: @concurrency_modifier,
              devcontainer_path: @devcontainer_path,
              configuration: @configuration,
            )
          end
        end
      end
    end

    context "proxy feature flags" do
      test "feature flags are proxied as an environment variable when flag enabled" do
        enable_feature_flag(:codespaces_prebuild_forward_vm_agent_feature_flags)

        feature_flags = GitHub::JSON.encode(Codespaces::Vscs.prebuild_feature_flags(@repository))

        # Ensure feature flags can be encoded as valid JSON
        json = JSON.parse(feature_flags)
        assert json.is_a?(Hash)
        json.each do |key, value|
          assert key.is_a?(String)
          assert [true, false].include?(value)
        end

        feature_flags_escaped = feature_flags.gsub('"', '\\"')
        expected_feature_flags_json = %{
      FEATURE_FLAGS_JSON: "#{feature_flags_escaped}"
        }

        yaml = build_workflow_yaml_with_devcontainer_path(@commit, @prebuild_hash, @repository, @region1, @configuration, "GitHub", GitHub.host_name_with_tenant, GitHub.api_url, GitHub.graphql_api_url, feature_flags: expected_feature_flags_json)

        expected_yaml = YAML.safe_load(yaml)

        workflow = Codespaces::CreatePrebuildTemplateDynamicWorkflow.new(
          repository: @repository,
          branch: @branch,
          locations: [@region1],
          commit_sha: @commit_sha,
          concurrency_modifier: @concurrency_modifier,
          configuration: @configuration,
          devcontainer_path: @devcontainer_path)

        result_yaml = YAML.safe_load(workflow.dynamic_workflow_yaml)

        # Check that the values in env are one of: string, number, boolean
        result_yaml_env = result_yaml["jobs"]["prebuild"]["env"]
        result_yaml_env.each do |key, value|
          # check type of value
          t = value.class
          if t == String || t == Integer || t == TrueClass || t == FalseClass
            # pass
          else
            # Fail test
            fail "Unsupported type '#{t}' for value of environment variable '#{key}'"
          end
        end

        # verify dynamic workflow yaml created matches expected yaml
        assert_equal expected_yaml, result_yaml

        @repository.expects(:run_dynamic_workflow).returns(
          @run_dynamic_workflow_twirp_result
        )

        result = Codespaces::CreatePrebuildTemplateDynamicWorkflow.call(
          repository: @repository,
          branch: @branch,
          locations: [@region1],
          concurrency_modifier: @concurrency_modifier,
          configuration: @configuration
        )

        assert_equal @run_dynamic_workflow_twirp_result, result
      end
    end

    context "larger storage size" do
      test "increased --storage-size argument is passed when codespaces_larger_storage_size is enabled" do
        enable_feature_flag(:codespaces_larger_storage_size)
        yaml = build_workflow_yaml_with_devcontainer_path(@commit, @prebuild_hash, @repository, @region1, @configuration, "GitHub", GitHub.host_name_with_tenant, GitHub.api_url, GitHub.graphql_api_url)

        expected_yaml = YAML.safe_load(yaml)

        workflow = Codespaces::CreatePrebuildTemplateDynamicWorkflow.new(
          repository: @repository,
          branch: @branch,
          locations: [@region1],
          commit_sha: @commit_sha,
          concurrency_modifier: @concurrency_modifier,
          configuration: @configuration,
          devcontainer_path: @devcontainer_path)

        result_yaml = YAML.safe_load(workflow.dynamic_workflow_yaml)
        assert result_yaml.dig("jobs", "prebuild", "steps").find { |step| step["name"] == "Create Template" }["run"].match(/--storage-size 256/)
        assert_equal expected_yaml, result_yaml

        @repository.expects(:run_dynamic_workflow).returns(
          @run_dynamic_workflow_twirp_result
        )

        result = Codespaces::CreatePrebuildTemplateDynamicWorkflow.call(
          repository: @repository,
          branch: @branch,
          locations: [@region1],
          concurrency_modifier: @concurrency_modifier,
          configuration: @configuration
        )

        assert_equal @run_dynamic_workflow_twirp_result, result
      end

      test "increased --storage-size argument is not passed when codespaces_larger_storage_size is disabled" do
        disable_feature_flag(:codespaces_larger_storage_size)
        yaml = build_workflow_yaml_with_devcontainer_path(@commit, @prebuild_hash, @repository, @region1, @configuration, "GitHub", GitHub.host_name_with_tenant, GitHub.api_url, GitHub.graphql_api_url)

        expected_yaml = YAML.safe_load(yaml)

        workflow = Codespaces::CreatePrebuildTemplateDynamicWorkflow.new(
          repository: @repository,
          branch: @branch,
          locations: [@region1],
          commit_sha: @commit_sha,
          concurrency_modifier: @concurrency_modifier,
          configuration: @configuration,
          devcontainer_path: @devcontainer_path)

        result_yaml = YAML.safe_load(workflow.dynamic_workflow_yaml)
        refute result_yaml.dig("jobs", "prebuild", "steps").find { |step| step["name"] == "Create Template" }["run"].match(/--storage-size 256/)
        assert_equal expected_yaml, result_yaml

        @repository.expects(:run_dynamic_workflow).returns(
          @run_dynamic_workflow_twirp_result
        )

        result = Codespaces::CreatePrebuildTemplateDynamicWorkflow.call(
          repository: @repository,
          branch: @branch,
          locations: [@region1],
          concurrency_modifier: @concurrency_modifier,
          configuration: @configuration
        )

        assert_equal @run_dynamic_workflow_twirp_result, result
      end
    end

    context "image allow list policy" do
      test "image_allow_list_policy is passed as an environment variable when present" do
        enable_feature_flag(:codespaces_enforce_image_allow_list_in_prebuild)
        enable_feature_flag(:codespaces_prebuild_forward_vm_agent_feature_flags)

        feature_flags = GitHub::JSON.encode(Codespaces::Vscs.prebuild_feature_flags(@repository)).gsub('"', '\\"')
        expected_feature_flags_json = %{
      FEATURE_FLAGS_JSON: "#{feature_flags}"
        }

        # Add a policy
        policy_group_org = create(:policy_group, owner: @org, name: "all repos")
        create(:policy_group_membership, policy_group: policy_group_org, target: @org)
        create(:policy_constraint, policy_group: policy_group_org, allowed_values: ["ghcr.io/test", "mcr.microsoft.com/devcontainers/*"], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_BASE_IMAGES)

        # NOTE: Line break and indentation matter here
        expected_image_allow_list_policy = '
      IMAGE_ALLOW_LIST_JSON: "[\"ghcr.io/test\",\"mcr.microsoft.com/devcontainers/*\"]"
        '

        yaml = build_workflow_yaml_with_devcontainer_path(@commit, @prebuild_hash, @repository, @region1, @configuration, "GitHub", GitHub.host_name_with_tenant, GitHub.api_url, GitHub.graphql_api_url, image_allow_list_policy: expected_image_allow_list_policy, feature_flags: expected_feature_flags_json)

        expected_yaml = YAML.safe_load(yaml)

        workflow = Codespaces::CreatePrebuildTemplateDynamicWorkflow.new(
          repository: @repository,
          branch: @branch,
          locations: [@region1],
          commit_sha: @commit_sha,
          concurrency_modifier: @concurrency_modifier,
          configuration: @configuration,
          devcontainer_path: @devcontainer_path)

        result_yaml = YAML.safe_load(workflow.dynamic_workflow_yaml)

        # Check that the values in env are one of: string, number, boolean
        result_yaml_env = result_yaml["jobs"]["prebuild"]["env"]
        result_yaml_env.each do |key, value|
          # check type of value
          t = value.class
          if t == String || t == Integer || t == TrueClass || t == FalseClass
            # pass
          else
            # Fail test
            fail "Unsupported type '#{t}' for value of environment variable '#{key}'"
          end
        end

        # verify dynamic workflow yaml created matches expected yaml
        assert_equal expected_yaml, result_yaml

        @repository.expects(:run_dynamic_workflow).returns(
          @run_dynamic_workflow_twirp_result
        )

        result = Codespaces::CreatePrebuildTemplateDynamicWorkflow.call(
          repository: @repository,
          branch: @branch,
          locations: [@region1],
          concurrency_modifier: @concurrency_modifier,
          configuration: @configuration
        )

        assert_equal @run_dynamic_workflow_twirp_result, result
      end

      test "image_allow_list_policy is omitted when policy group is set but no image policy is set" do
        enable_feature_flag(:codespaces_enforce_image_allow_list_in_prebuild)

        # Create a policy group but DO NOT add an image allow list policy
        policy_group_org = create(:policy_group, owner: @org, name: "all repos")
        create(:policy_group_membership, policy_group: policy_group_org, target: @org)

        expected_yaml = YAML.safe_load(@workflow_yaml)

        workflow = Codespaces::CreatePrebuildTemplateDynamicWorkflow.new(
          repository: @repository,
          branch: @branch,
          locations: [@region1],
          commit_sha: @commit_sha,
          concurrency_modifier: @concurrency_modifier,
          configuration: @configuration,
          devcontainer_path: @devcontainer_path)

        result_yaml = YAML.safe_load(workflow.dynamic_workflow_yaml)

        # verify dynamic workflow yaml created matches expected yaml
        assert_equal expected_yaml, result_yaml

        @repository.expects(:run_dynamic_workflow).returns(
          @run_dynamic_workflow_twirp_result
        )

        result = Codespaces::CreatePrebuildTemplateDynamicWorkflow.call(
          repository: @repository,
          branch: @branch,
          locations: [@region1],
          concurrency_modifier: @concurrency_modifier,
          configuration: @configuration
        )

        assert_equal @run_dynamic_workflow_twirp_result, result
      end

      test "image_allow_list_policy is omitted when no policy group is set" do
        enable_feature_flag(:codespaces_enforce_image_allow_list_in_prebuild)
        expected_yaml = YAML.safe_load(@workflow_yaml)

        workflow = Codespaces::CreatePrebuildTemplateDynamicWorkflow.new(
          repository: @repository,
          branch: @branch,
          locations: [@region1],
          commit_sha: @commit_sha,
          concurrency_modifier: @concurrency_modifier,
          configuration: @configuration,
          devcontainer_path: @devcontainer_path)

        result_yaml = YAML.safe_load(workflow.dynamic_workflow_yaml)

        # verify dynamic workflow yaml created matches expected yaml
        assert_equal expected_yaml, result_yaml

        @repository.expects(:run_dynamic_workflow).returns(
          @run_dynamic_workflow_twirp_result
        )

        result = Codespaces::CreatePrebuildTemplateDynamicWorkflow.call(
          repository: @repository,
          branch: @branch,
          locations: [@region1],
          concurrency_modifier: @concurrency_modifier,
          configuration: @configuration
        )

        assert_equal @run_dynamic_workflow_twirp_result, result
      end
    end
  end
end unless GitHub.enterprise?
