# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    class CopilotJavaUpgradeAgent < BaseProcessor
      DEFAULT_GROUP_ID = "github-#{Rails.env}-copilot_java_upgrade_agent"
      DEFAULT_SUBSCRIBE_TO = /github\.v1\.IssueUpdateLabel\Z/

      CODEPATH_COPILOT_JAVA_UPGRADE_AGENT_PROCESSOR = "copilot_java_upgrade_agent_processor"

      options[:session_timeout] = 60.seconds
      options[:socket_timeout] = 65.seconds
      options[:start_from_beginning] = false

      # Public: Configure the Hydro processor
      def setup(**kwargs)
        options[:group_id] ||= DEFAULT_GROUP_ID
        options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO
      end

      # Public: Process a single Hydro message
      #
      # message - The Hydro message to process
      #
      # Returns nothing
      def process_message(message)
        repository_id = message.value.dig(:repository, :id)
        repo = Repository.find_by(id: repository_id)

        # Verify java upgrade enabled for the repository
        return message.skip("repository_not_found") unless repo
        return message.skip("java_upgrade_agent_not_enabled") unless repo.feature_enabled?(:copilot_java_upgrade_agent)

        # Verify copilot java upgrade label
        action = message.value[:action]
        return message.skip("not_a_label_assignment") unless action == "issue.events.labeled"
        copilot_java_upgrade_label = message.value[:labels]&.find { |a| a[:name] == "copilot-java-upgrade" }
        return message.skip("not_a_copilot_java_upgrade_assignment") unless copilot_java_upgrade_label

        # Verify copilot java upgrade installation
        # integration_id = Integration.find_by(name: "copilot-java-upgrade")&.id
        # integration = IntegrationInstallation
        #       .with_repository(repo)
        #       .where(integration_id: integration_id)
        #       .first
        # return message.skip("copilot_java_upgrade_integration_not_found") unless integration

        # Verify issue is a java upgrade issue
        number = message.value.dig(:issue, :number)
        issue = repo.issues.find_by(number: number)
        return message.skip("issue_not_found") unless issue
        return message.skip("not_a_java_upgrade") unless issue.body&.include?("Upgrade the java projects")

        # Get user that assigned label to issue
        label_assignee = message.value[:actor]
        return message.skip("label_assignee_not_a_user") unless label_assignee[:type] == :USER
        user = User.find_by(id: label_assignee[:id])
        return message.skip("label_assignee_user_not_found") unless user

        # Find Inputs
        current_java_version = issue.body&.match(/Current Java Version: (.+)/)&.[](1)&.strip
        new_java_version = issue.body&.match(/New Java Version: (.+)/)&.[](1)&.strip
        return message.skip("java_version_inputs_required") unless current_java_version && new_java_version

        on_container_command_params = {
          type: "javaUpgrade",
          currentJavaVersion: current_java_version,
          newJavaVersion: new_java_version,
          issueNumber: number,
          repoName: repo.nwo,
        }

        environment_options = environment_options_for_repo(on_container_command_params: on_container_command_params)

        # Create Codespace async to perform the upgrade
        ActiveRecord::Base.connected_to(role: :writing) do
          CloudEnvironments::Public.create_ephemeral(attributes: build_attributes(repo:, current_user: user),
            environment_options: environment_options,
            stats_tagger: stats_tagger(repo:, current_user: user),
            entry_point: nil,
            operation: ::Codespaces::AsyncOperation.create!(user: user, operation: :create_codespace)
          )
        rescue => e # rubocop:disable Lint/GenericRescue
          return message.skip("codespace_creation_failed_with_exception_#{e}")
        end
      end

      private

      def build_attributes(repo:, current_user:)
        ref = "refs/heads/#{repo.default_branch}"
        location = ::Codespaces::GetRegionForUser.call(user: current_user, repository: repo, client: :dotcom)
        vscs_target = ::Codespaces::Vscs.default_target
        billable_owner = ::Codespaces::RepositoryPolicy.async_with_prefill(current_user, repo).sync.billable_owner

        default_sku = ::Codespaces::Skus.default_sku(
          repository: repo,
          owner: current_user,
          location: location,
          ref: ref,
          billable_owner: billable_owner,
          vscs_target: vscs_target
        )&.name&.to_s

        ref_for_oid = ::Codespaces::GetTargetRef.call(repository: repo, name_or_oid: ref)
        oid = ref_for_oid&.target_oid
        devcontainer_path = ::Codespaces::DevContainer.get_default_path(repo, oid)

        plan_attrs = {
          location: location,
          vscs_target: vscs_target,
        }
        plan = ::Codespaces::Plan.for!(**plan_attrs)

        {
          owner: current_user,
          repository_id: repo.id,
          ref: ref,
          oid: oid,
          billable_owner: billable_owner,
          vscs_target: vscs_target,
          retention_period_minutes: 1440,
          sku_name: default_sku,
          location: location,
          plan: plan,
          devcontainer_path: devcontainer_path,
        }
      end

      def environment_options_for_repo(on_container_command_params:)
        {
          autoShutdownDelay: 120,
          experimentalFeatures: {
            system_on_container_command_params: on_container_command_params
          }
        }
      end

      def stats_tagger(repo:, current_user:)
        CloudEnvironments::StatsTagger.new(
           vscs_target: ::Codespaces::Vscs.default_target,
           user: current_user,
           location: ::Codespaces::GetRegionForUser.call(user: current_user, repository: repo, client: :dotcom),
         )
      end

      # def generate_token(repo:, integration:)
      #   entry_point = Permissions::Service::EntryPoint.build(
      #     :twirp_api_copilot_agent_handler, # TODO: should we create a new entry point?
      #     target: repo.owner,
      #     actor_owner: integration,
      #   )

      #   # DOUBLE CHECK THIS
      #   result = ScopedIntegrationInstallation::Creator.perform_with_cache(
      #     integration,
      #     repositories: [repo],
      #     permissions: integration.permissions,
      #     entry_point: entry_point,
      #   )

      #   installation = result.installation

      #   # ENSURE EXPIRY IS AT LEAST 2 HOURS
      #   record, token = installation.generate_token(code_path: CODEPATH_COPILOT_JAVA_UPGRADE_AGENT_PROCESSOR)
      #   token
      # end
    end
  end
end
