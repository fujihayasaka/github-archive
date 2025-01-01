# typed: true
# frozen_string_literal: true

module Codespaces
  class CreatePrebuildTemplateDynamicWorkflow < Command
    class Error < Codespaces::Error; end
    class InvalidRegionError < Error; end
    class AuthorizationError < Error; end
    class InvalidBranchError < Error; end
    class InvalidVSCSTargetAndUrlError < Error; end
    class RunDynamicWorkflowError < Error; end

    include GitHub::Memoizer

    IMAGE_ALLOW_LIST_JSON = "IMAGE_ALLOW_LIST_JSON".freeze
    FEATURE_FLAGS_JSON = "FEATURE_FLAGS_JSON".freeze
    RUNNER_PREBUILD_IMAGE = "codespaces-prebuild".freeze

    attr_reader :repository, :branch, :locations, :vscs_target, :vscs_target_url, :commit_sha, :concurrency_modifier, :configuration, :devcontainer_path, :use_storage_v2

    def initialize(repository:, branch:, locations:, concurrency_modifier:, vscs_target: Codespaces::Vscs.default_target, devcontainer_path: nil, vscs_target_url: nil, commit_sha: nil, configuration: nil)
      @repository = repository
      @branch = branch
      @locations = locations # array of locations
      @vscs_target = vscs_target.to_sym
      @vscs_target_url = vscs_target_url
      @commit_sha = commit_sha || @repository.ref_to_sha(@branch)
      @concurrency_modifier = concurrency_modifier
      @devcontainer_path = devcontainer_path
      @configuration = configuration # optional, this command does not need to be depenend on a configuration exisiting
      @use_storage_v2 = GitHub.flipper[storage_v2_prebuild_flag_name].enabled?(repository) || (GitHub.flipper[storage_v2_prebuild_flag_name].enabled?(repository.business || repository.owner))
    end

    def perform
      validate!

      GitHub.logger.info(
        "Kicking off Codespaces Prebuild Create Template Dynamic Workflow",
        "gh.repo.id" => repository.id,
        "gh.codespaces.prebuilds.configuration.id" => configuration&.id,
        "gh.codespaces.regions" => regions,
        "gh.codespaces.vscs_target" => vscs_target,
        "gh.codespaces.use_storage_v2" => use_storage_v2,
        "code.namespace" => "Codespaces::CreatePrebuildTemplateDynamicWorkflow",
      )

      repository.run_dynamic_workflow(
        actor: codespaces_bot,
        workflow: dynamic_workflow_yaml,
        inputs: nil,
        ref: branch, # ref that is going to available in `github.ref`. Must be a branch.
        workflow_name: Codespaces::Prebuilds.workflow_name(vscs_target), # name to display in the workflow run list
        slug: Codespaces::Prebuilds.workflow_slug(vscs_target), # slug to use in the workflow run list
        integration_name: Apps::Internal::Codespaces::PREBUILD_DYNAMIC_WORKFLOW_INTEGRATION_NAME,
        entry_point: :codespaces_commands_create_prebuild_template_dynamic_workflow
      ).tap do |result|
        if result&.call_succeeded
          configuration&.update!(latest_workflow_run_id: result.value.workflow_run_id)
          notify_prebuild_configuration_workflow_run_update(configuration)

          GitHub.logger.info(
            "Codespaces Prebuild Create Template Dynamic Workflow successfully kicked off",
            "gh.repo.id" => repository.id,
            "gh.repo.owner.login" => repository.owner.display_login,
            "gh.codespaces.prebuilds.configuration.id" => configuration&.id,
            "gh.codespaces.prebuild_hash" => prebuild_hash,
            "gh.codespaces.regions" => regions,
            "gh.codespaces.prebuild.workflow_run_id" => result&.value&.workflow_run_id,
            "gh.codespaces.vscs_target" => vscs_target,
            "gh.codespaces.use_storage_v2" => use_storage_v2,
            "code.namespace" => "Codespaces::CreatePrebuildTemplateDynamicWorkflow",
          )
        else
          message = result&.status == 422 && result&.options.has_key?(:message) ? result&.options[:message] : "unknown error"
          Failbot.report(RunDynamicWorkflowError.new("invalid response from run_dynamic_workflow: #{message}"))
        end
      end
    end

    def dynamic_workflow_yaml
      if use_storage_v2
        steps = steps_for_storage_v2
      else
        steps = steps_for_storage_v1
      end

      unless repository.feature_enabled?(:codespaces_remove_prebuild_artifacts)
        # when we remove this FF, we can also remove the env var: LOG_PATH
        # and secret variable: GITHUB_CODESPACES_LOG_PATH
        steps.push(workflow_artifact_step)
      end

      if repository.feature_enabled?(:codespaces_prebuild_runner_choice) &&
        configuration&.runner_label.present? &&
        configuration&.runner_group.present?

        runs_on = {
          group: configuration.runner_group,
          label: configuration.runner_label
        }
      elsif repository.feature_enabled?(:codespaces_template_repo_prebuild_label)
        runs_on = "template-repo-prebuild-pool"
      elsif repository.feature_enabled?(:codespaces_custom_runner_label)
        runs_on = "custom-codespaces-prebuild"
      else
        runs_on = RUNNER_PREBUILD_IMAGE
      end

      prebuild_job = {
        "runs-on": runs_on,
        steps: steps,
        env: env
      }

      # These are the permissions granted to the GITHUB_TOKEN on the Actions workflow (passed to the Codespace Agent as
      #`CODESPACES_GITHUB__APITOKEN`) which is used for making requests to the codespaces API to register the template
      # with the monolith/service after the template has been built and stored.
      # We are passing empty permissions here because otherwise the default permissions will be granted. Default
      # permissions are a repository setting which could grant all or some write permissions that are not needed. The
      # only scope needed is the special `codespaces_prebuild` permission which is granted in the Actions Launch service,
      # only to this Codespaces-owned dynamic workflow.
      if GitHub.flipper[:codespaces_prebuilds_empty_permissions].enabled?(repository)
        prebuild_job[:permissions] = {}
      end

      if codespaces_prebuilds_allow_token_write?
        prebuild_job[:permissions] = {
          contents: "read",
          "id-token": "write"
        }
      end

      {
        name: dynamic_workflow_name,
        on: "dynamic",
        concurrency: concurrency_key,
        defaults: {
          run: {
            shell: "sudo -EH bash {0}"
          }
        },
        jobs: {
          prebuild: prebuild_job
        },
      }.deep_stringify_keys.to_yaml(line_width: -1).gsub("---\n", "")
    end

    private

    memoize def organization
      repository.owner.organization? ? repository.owner : nil
    end

    memoize def enterprise
      if repository.owner.organization?
        organization&.business
      # in an a multi-tenant context the repo could be owned by a user. In those cases
      # return the current tenant so that enterprise data is still returned in the response
      # can't use GitHub.CurrentTenant because this may be called from an internal API as an unscoped request
      elsif GitHub.multi_tenant_enterprise? && repository.owner.user?
        repository.user.enterprise_managed_business
      end
    end

    memoize def codespaces_prebuilds_allow_token_write?
      GitHub.flipper[:codespaces_prebuilds_allow_token_write].enabled?(repository) || GitHub.flipper[:codespaces_prebuilds_allow_token_write].enabled?(organization) || GitHub.flipper[:codespaces_prebuilds_allow_token_write].enabled?(enterprise)
    end

    def validate!
      unless repository&.owner.codespaces_feature_enabled?
        raise AuthorizationError, "this repository does not support this feature"
      end

      Codespaces::ValidatePrebuildAccess.call(repository: repository, vscs_target: vscs_target, vscs_target_url: vscs_target_url)
      raise InvalidVSCSTargetAndUrlError unless vscs_target_valid?
      raise InvalidRegionError unless all_regions_valid?
      raise InvalidBranchError unless repository.branch_exists?(branch)
    end

    def all_regions_valid?
      valid_locations = Codespaces::VscsServiceStamp.where(vscs_target:, prebuild_templates_allowed: true).map { |stamp| stamp.region.id }
      (locations - valid_locations).empty?
    end

    def vscs_target_valid?
      if vscs_target == :local && vscs_target_url.blank?
        return false
      elsif vscs_target != :local && vscs_target_url.present?
        return false
      end
      true
    end

    def prebuild_hash
      return @prebuild_hash if defined?(@prebuild_hash)
      @prebuild_hash = Codespaces::CalculatePrebuildHash.call(repository: repository, oid: commit_sha, devcontainer_path: devcontainer_path)
    end

    def dynamic_workflow_name
      return @workflow_name if defined?(@workflow_name)

      commit = repository.commits.find(commit_sha)
      @workflow_name = commit.present? ? "[#{branch}]: #{commit.short_message_text}" : "`#{branch}` #{commit_sha}"
    end

    def concurrency_key
      "#{prebuild_hash}-#{concurrency_modifier}"
    end

    def steps_for_storage_v1
      [
        {
          name: "Mask secrets",
          run: mask_secrets
        },
        {
          name: "Install Agent",
          run: install_agent,
        },
        {
          name: "Create Template",
          run: create_template,
        },
        {
          name: "Upload Template",
          run: upload_template,
        }
      ]
    end

    def steps_for_storage_v2
      [
        {
          name: "Mask secrets",
          run: mask_secrets
        },
        {
          name: "Install Agent",
          run: install_agent,
        },
        {
          name: "Create Template",
          run: create_template_v2,
        },
        {
          name: "Upload Template",
          run: upload_templates,
        }
      ]
    end

    def workflow_artifact_step
      {
        name: "Save Creation Logs",
        if: "always()",
        uses: "actions/upload-artifact@v2",
        with: {
          name: "logs",
          path: "${{ env.LOG_PATH }}"
        },
      }
    end

    # We mask these secrets in the workflow so that they are not visible in the logs
    # The secrets are stored in the `USER_SECRETS_JSON` environment variable when launch fetches the secrets
    # These secrets can be user input as well as default ones we set in AssembleSecrets
    def mask_secrets
      remove_null = 'or .value=="" or .value==null'

      remove_default_non_secrets = safe_non_secrets.concat([repository.name_with_display_owner]).uniq.map do |non_secret|
        ".value==\"#{non_secret}\""
      end.join(" or ")

      <<~SHELL
        echo -e $USER_SECRETS_JSON | jq 'del(.[] |
          select(#{remove_default_non_secrets} #{remove_null}))' |
          jq 'unique_by(.value)' | jq .[] | jq '.value[]? // .value?' |jq -r \\\"::add-mask::\\\"+'.?'
      SHELL
    end

    # We don't want to mask the word GitHub or our urls in logs, this could lead to confusing logs
    memoize def safe_non_secrets
      [
        GitHub.web_committer_name,
        GitHub.web_committer_email,
        GitHub.url,
        GitHub.api_url,
        GitHub.graphql_api_url,
      ]
    end

    # AGENT_DOWNLOAD_URL uses github.repository which currenty contains the tenant suffix in the nwo
    # The API will soon not support nwo with tenant suffixes: https://github.com/github/proxima/issues/1580
    # We will need to track actions updating (https://github.com/github/actions-delta/issues/320) this variable to remove the tenant suffix otherwise once #1580 is done we will start to fail downloading the agent
    def install_agent
      <<~YAML
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
      YAML
    end

    def inject_env_into_user_secrets
      if codespaces_prebuilds_allow_token_write?
        # Append ACTIONS_ID_TOKEN_REQUEST_URL and ACTIONS_ID_TOKEN_REQUEST_TOKEN to USER_SECRETS_JSON
        <<~YAML
          # Merge token secrets
          export USER_SECRETS_JSON=$(echo -e $USER_SECRETS_JSON | jq --arg url "$ACTIONS_ID_TOKEN_REQUEST_URL" --arg token "$ACTIONS_ID_TOKEN_REQUEST_TOKEN" '. + [{"type": "EnvironmentVariable", "name": "ACTIONS_ID_TOKEN_REQUEST_URL", "value": $url}, {"type": "EnvironmentVariable", "name": "ACTIONS_ID_TOKEN_REQUEST_TOKEN", "value": $token}]')
        YAML
      else
        ""
      end
    end

    def create_template
      inject_env_into_user_secrets + if devcontainer_path.present?
        <<~YAML
          # Create
          /.codespaces/agent/bin/codespaces prebuild create --repo-url $REPO_URL_WITHOUT_BRANCH --repo-name-no-owner $REPO_NAME_WITHOUT_OWNER --branch ${{ github.ref_name }} --devcontainer-path $DEVCONTAINER_PATH --commit ${{ github.sha }} --config-id $CONFIGURATION_ID --user-secrets-env USER_SECRETS_JSON#{image_allow_list_policy_vmagent_arg}#{feature_flag_arg}#{larger_storage_size_arg}
          YAML
      else
        <<~YAML
          # Create
          /.codespaces/agent/bin/codespaces prebuild create --repo-url $REPO_URL_WITHOUT_BRANCH --repo-name-no-owner $REPO_NAME_WITHOUT_OWNER --branch ${{ github.ref_name }} --commit ${{ github.sha }} --config-id $CONFIGURATION_ID --user-secrets-env USER_SECRETS_JSON#{image_allow_list_policy_vmagent_arg}#{feature_flag_arg}#{larger_storage_size_arg}
          YAML
      end
    end

    def create_template_v2
      inject_env_into_user_secrets + if devcontainer_path.present?
        <<~YAML
        # Create
        /.codespaces/agent/bin/codespaces prebuild create --repo-url $REPO_URL_WITHOUT_BRANCH --repo-name-no-owner $REPO_NAME_WITHOUT_OWNER --branch ${{ github.ref_name }} --devcontainer-path $DEVCONTAINER_PATH --commit ${{ github.sha }} --config-id $CONFIGURATION_ID --user-secrets-env USER_SECRETS_JSON#{image_allow_list_policy_vmagent_arg}#{feature_flag_arg}#{storage_v2_prebuild_create_arg}
        YAML
      else
        <<~YAML
        # Create
        /.codespaces/agent/bin/codespaces prebuild create --repo-url $REPO_URL_WITHOUT_BRANCH --repo-name-no-owner $REPO_NAME_WITHOUT_OWNER --branch ${{ github.ref_name }} --commit ${{ github.sha }} --config-id $CONFIGURATION_ID --user-secrets-env USER_SECRETS_JSON#{image_allow_list_policy_vmagent_arg}#{feature_flag_arg}#{storage_v2_prebuild_create_arg}
        YAML
      end
    end

    def shrink_template
      <<~YAML
      # Shrink
      /.codespaces/agent/bin/codespaces prebuild shrink
      YAML
    end

    def upload_templates
      yaml = ""
      unless repository.feature_enabled?(:codespaces_prebuilds_skip_v1_upload)
        yaml += upload_template
      end

      yaml += upload_template_v2
    end

    def upload_template
      if devcontainer_path.present?
        <<~YAML
          for location in $TARGET_VSCS_LOCATIONS; do
            /.codespaces/agent/bin/codespaces prebuild upload --location $location --repo-name ${{ github.repository }} --devcontainer-path $DEVCONTAINER_PATH --config-id $CONFIGURATION_ID
          done
          YAML
      else
        <<~YAML
          for location in $TARGET_VSCS_LOCATIONS; do
            /.codespaces/agent/bin/codespaces prebuild upload --location $location --repo-name ${{ github.repository }} --config-id $CONFIGURATION_ID
          done
          YAML
      end
    end

    def upload_template_v2
      yaml = <<~YAML
      # Generate manifest
      /.codespaces/agent/bin/codespaces prebuild manifest --config-id $CONFIGURATION_ID#{storage_v2_image_version_arg}
      YAML

      yaml += get_v2_concurrent_yaml_template
    end

    def get_v2_concurrent_yaml_template
      # create the multivalue parmeter in the dotnet style https://natemcmaster.github.io/CommandLineUtils/v2.2/api/McMaster.Extensions.CommandLineUtils.CommandOptionType.html
      target_locations = []
      locations.each do |location|
        target_locations.push("--target-locations #{location}")
      end
      target_locations = target_locations.join(" ")
      if devcontainer_path.present?
        <<~YAML
        # Upload templates
        /.codespaces/agent/bin/codespaces prebuild upload --storage-type v2 #{target_locations} --repo-name ${{ github.repository }} --devcontainer-path $DEVCONTAINER_PATH --config-id $CONFIGURATION_ID#{storage_v2_prebuild_upload_arg}#{feature_flag_arg}
        YAML
      else
        <<~YAML
        # Upload templates
        /.codespaces/agent/bin/codespaces prebuild upload --storage-type v2 #{target_locations} --repo-name ${{ github.repository }} --config-id $CONFIGURATION_ID#{storage_v2_prebuild_upload_arg}#{feature_flag_arg}
        YAML
      end
    end

    # Variables that constitute Codespaces Agent settings have a prefix "CODESPACES_"
    def env
      result = {
        CODESPACES_GITHUB__APITOKEN: "${{ secrets.GITHUB_TOKEN }}",
        CODESPACES_GITHUB__VSCSTARGET: vscs_target.to_s,
        CODESPACES_GITHUB__WORKFLOWRUNID: "${{ github.run_id }}",
        CODESPACES_GITHUB__APIURLBASE: GitHub.api_url,
        CODESPACES_TELEMETRYSETTINGS__TELEMETRYENDPOINT: "${{ secrets.GITHUB_CODESPACES_INTERNAL_URL }}/${{ github.repository }}/agent/diagnostics",
        TARGET_VSCS_LOCATIONS: regions,
        USER_SECRETS_JSON: "${{secrets.GITHUB_CODESPACE_AGENT_SECRETS}}",
        REPO_URL: "${{ github.server_url }}/${{ github.repository }}/tree/${{ github.ref_name }}",
        REPO_URL_WITHOUT_BRANCH: "${{ github.server_url }}/${{ github.repository }}",
        REPO_NAME_WITHOUT_OWNER: repository.name,
        DEVCONTAINER_PATH: devcontainer_path.to_s,
        CONFIGURATION_ID: configuration&.id,
        CODESPACES_GITHUB__VSCSTARGETURL: vscs_target_url.to_s,
        INTERNAL_URL: "${{ secrets.GITHUB_CODESPACES_INTERNAL_URL }}",
        LOG_PATH: "${{ secrets.GITHUB_CODESPACES_LOG_PATH}}",
        TARGET_KEY: "${{ secrets.GITHUB_CODESPACES_TARGET_KEY }}",
        TARGET_LOCATION_KEY: "${{ secrets.GITHUB_CODESPACES_LOCATION_KEY }}",
        TARGET_URL_KEY: "${{ secrets.GITHUB_CODESPACES_TARGET_URL_KEY }}"
      }

      # Pass along image allow list policy if non-empty
      if image_allow_list_policy_env.present?
        result[IMAGE_ALLOW_LIST_JSON] = image_allow_list_policy_env
      end

      # Pass along feature flags enabled for the owner of this repository
      if feature_flag_env.present?
        result[FEATURE_FLAGS_JSON] = feature_flag_env
      end

      result
    end

    def regions
      @regions ||= locations.join(" ")
    end

    memoize def image_allow_list_policy_env
      return "" unless GitHub.flipper[:codespaces_enforce_image_allow_list_in_prebuild].enabled?(repository)
      allowed_images = Codespaces::ImagePolicy.merged_allowlists(billable_owner: repository.owner, repository:)
      return "" unless allowed_images.present?
      GitHub::JSON.encode(allowed_images)
    end

    def image_allow_list_policy_vmagent_arg
      return "" unless image_allow_list_policy_env.present?
      # VM Agent expects a string with the *name* of the environment variable
      " --image-allow-list-env #{IMAGE_ALLOW_LIST_JSON}"
    end

    def larger_storage_size_arg
      return "" unless GitHub.flipper[:codespaces_larger_storage_size].enabled?(repository)
      # Some repos require more storage space than the default max 128GB
      " --storage-size 256"
    end

    memoize def feature_flag_env
      return "" unless GitHub.flipper[:codespaces_prebuild_forward_vm_agent_feature_flags].enabled?(repository)
      feature_flags = Codespaces::Vscs.prebuild_feature_flags(repository)
      GitHub::JSON.encode(feature_flags)
    end

    def feature_flag_arg
      return "" unless feature_flag_env.present?
      # VM Agent expects a string with the *name* of the environment variable
      " --features-env #{FEATURE_FLAGS_JSON}"
    end

    memoize def codespaces_bot
      Integration.find_by(key: GitHub.codespaces_app_key)&.bot
    end

    memoize def storage_v2_prebuild_flag_name
      target_suffix = vscs_target == Codespaces::Vscs.default_target.to_sym ? "" : "_#{vscs_target}"
      "codespaces_storage_v2_prebuilds#{target_suffix}"
    end

    memoize def storage_v2_prebuild_create_arg
      "#{storage_v2_image_version_arg} --storage-size 256"
    end

    memoize def storage_v2_prebuild_upload_arg
      image_version = storage_v2_image_version_arg.empty? ? " --image-version Minimal" : storage_v2_image_version_arg
      " --flush-only#{image_version}"
    end

    memoize def storage_v2_image_version_arg
      target_suffix = vscs_target == Codespaces::Vscs.default_target.to_sym ? "" : "_#{vscs_target}"
      raw_version_feature_flag = "codespaces_storage_v2_prebuilds_raw_only#{target_suffix}"
      multi_versions_feature_flag = "codespaces_storage_v2_prebuilds_multi#{target_suffix}"

      if repository.feature_enabled?(multi_versions_feature_flag)
        " --image-version Minimal --image-version Raw"
      elsif repository.feature_enabled?(raw_version_feature_flag)
        " --image-version Raw"
      else
        ""
      end
    end

    def notify_prebuild_configuration_workflow_run_update(prebuild_configuration)
      if prebuild_configuration.present?
        GlobalInstrumenter.instrument("prebuild_configuration_workflow_run.update", {
          prebuild_configuration_id: prebuild_configuration.id,
        })
      end
    end
  end
end
