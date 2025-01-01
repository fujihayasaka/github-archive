# frozen_string_literal: true

require_relative "../runner"
# Do not require anything else here. If you need something for your runner, put that in `self.run`.
# This makes sure the boot time of our seeds stays low.

module Seeds
  class Runner
    class Workbench < Seeds::Runner
      def self.help
        <<~HELP
        - Adds github/workbench-template and github/spark-template in local environment, enables FF
        HELP
      end

      def self.run(options = {})
        require_relative "../factory_bot_loader"

        user = Seeds::Objects::User.monalisa
        puts "--- Creating features ---"
        enable_feature_flags(user)

        puts "--- Creating github/workbench-template and github/spark-template"
        create_workbench_template(user)

        puts "--- Enabling Sonnet policy"
        enable_sonnet_policy
      end

      def self.enable_sonnet_policy
        # this org should be created as part of seeds/runners/copilot4prs.rb
        org_on_copilot_enterprise_name = "copilot-enterprise-org"
        org = Organization.find_by(login: org_on_copilot_enterprise_name)
        return unless org

        puts "enabling Claude Sonnet 3.7 for #{org_on_copilot_enterprise_name}"
        ::Copilot::Business.new(org.business).a_f_enabled!

        puts "enabling Claude Sonnet 4 for #{org_on_copilot_enterprise_name}"
        ::Copilot::Business.new(org.business).afos_enabled!
      end

      # copilot_api_model_rollout_claude_afos_copilot_chat_dev_users is required for sonnet 4
      def self.enable_feature_flags(user)
        flags = %i{
          copilot_workbench
          dotcom_chat_client_side_skills
          copilot_workbench_redirect
          copilot_workbench_monaco_wasm
          copilot_workbench_kv_payload_limit
          copilot_spark_single_user_iteration
          copilot_api_enable_model_claude_afos_anthropic
          copilot_api_model_rollout_claude_afos_spark_agent_dev_users
          copilot_api_model_rollout_claude_afos_copilot_chat_dev_users
          copilot_workbench_debug_panel
          spark_pull_from_repository
          spark_sync_repository_after_iteration
          spark_api_errors
          spark_kv_get_404
          spark_aca_regions
        }

        flags.each do |flag|
          puts "Enabling :#{flag} for #{user}"
          Seeds::Objects::FeatureFlag.enable(feature_flag: flag, actor: user)
        end

        # Disable copilot_api_enable_model_claude37sonnet_gcp_useast5 so that we
        # don't try to use GCP for Claude 3.7 in CAPI in dev, since that won't
        # work
        Seeds::Objects::FeatureFlag.disable(feature_flag: "copilot_api_enable_model_claude37sonnet_gcp_useast5", actor: user)

        # Disable copilot_workbench_session_snapshot since it does not work in
        # dev and will cause 500s on POST /spark
        Seeds::Objects::FeatureFlag.disable(feature_flag: "copilot_workbench_session_snapshot", actor: user)
      end

      # External setup script will grab contents from github to this location
      def self.create_workbench_template(user)
        puts "Creating github/workbench-template"
        repo = Seeds::Objects::Repository.create(
          owner_name: "github",
          repo_name: "workbench-template",
          is_public: true,
          setup_master: false,
          template: true,
        )

        puts "Creating github/spark-template"
        spark_repo = Seeds::Objects::Repository.create(
          owner_name: "github",
          repo_name: "spark-template",
          is_public: true,
          setup_master: false,
          template: true,
        )
      end
    end
  end
end
