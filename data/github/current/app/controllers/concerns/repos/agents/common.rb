# typed: true
# frozen_string_literal: true

# Shared helpers for controllers in the repo-agents React app.
#
# Provides the common before_actions, sidebar payload helpers, and render
# configuration that both TasksController and AutomationsController need.
#
# Include in any controller that renders within the repo-agents React app.
module Repos
  module Agents
    module Common
      extend ActiveSupport::Concern
      extend T::Helpers
      include GitHub::Memoizer
      include MissionControlExperimentEvents

      requires_ancestor { AbstractRepositoryController }

      included do
        T.bind(self, T.class_of(AbstractRepositoryController))
        include ApplicationController::JsonDependency

        before_action :login_required
        before_action :require_copilot_swe_agent_enabled
      end

      class_methods do
        sig { returns(String) }
        def react_bundle_name
          "repo-agents"
        end
      end

      COPILOT_SETUP_STEPS_PATH = ".github/workflows/copilot-setup-steps.yml"

      # Standard turbo frame config for soft-nav within the repo-agents app.
      TURBO_CONFIG = {
        id: "repo-content-turbo-frame",
        target: "_top",
        action: "advance",
      }.freeze

      # Standard page_data for all repo-agents views.
      PAGE_DATA = {
        hide_footer: true,
        selected_link: :repo_agents,
      }.freeze

      private

      sig { returns(T.nilable(Symbol)) }
      def global_nav_selected_link
        :repo_agents
      end

      def repo_data
        Repos::ReactPayload.current_repository_payload(
          current_repository,
          current_user_can_push: current_user_can_push?,
        )
      end

      # Shared payload props sent by all controllers in the repo-agents app.
      # NOTE: This must stay in sync with BaseRepoAgentsPayload in github-ui
      def base_payload_props(user)
        token = CopilotSessions::CopilotApiToken.get_encrypted(
          user:,
          entry_point: :agents_common,
          user_session: user_session
        )
        sso_org_ids = saml_for_user.protected_organization_ids.map(&:to_s)

        result = {
          repository: repo_data,
          currentUser: CopilotSessions::Payloads::PublicUser.new(user).call,
          copilotMemoryEnabled: copilot_memory_enabled?,
          copilotSetupStepsFilePath: copilot_setup_steps_file_path,
          copilotCodingAgentEnabled: copilot_coding_agent_enabled?,
          copilotCodingAgentEnabledForRepo: copilot_coding_agent_enabled_for_repo?,
          hasPaidCopilotAccess: has_paid_copilot_access?,
          hasCEorCBAccess: has_ce_or_cb_access?,
          userHasCCAByPolicy: user_has_cca_by_policy?,
          userHasCodeReviewAccess: user_has_code_review_access?,
          hasAgentsMd: has_agents_md?,
          automationsVisible: automations_visible_for_current_user?,
          orgAllowReadAccessTriggers: org_allow_read_access_triggers_policy,
          repoAllowReadAccessTriggers: repo_allow_read_access_triggers_policy,
        }

        if token
          result[:initialAuthToken] = {
            token: token.value,
            expiration: token.expiration&.iso8601,
            ssoOrgIDs: sso_org_ids,
          }
        end

        result
      end

      def require_copilot_swe_agent_enabled
        render_404 unless agents_enabled?
      end

      memoize def agents_enabled?
        return true if user_can_use_cca?

        # CCR fallback: allow Copilot Code Review users to view CCR sessions
        return true if user_has_code_review_access?

        # Non-CCA fallback: allow CLI / GitHub App users even without CCA
        if FeatureFlag.vexi.enabled?(:copilot_mission_control_cli_remote, current_user, default: false)
          copilot_user = Copilot::Public::User.for(current_user)
          copilot_user.cloud_agent_sessions_visible?
        else
          false
        end
      end

      # Strict check: user's own policy allows CCA on this repo
      memoize def user_can_use_cca?
        current_repository.copilot_swe_agent_enabled?(current_user)
      end

      memoize def user_has_cca_by_policy?
        Copilot::Public::User.for(current_user).swe_agent_enabled?
      end

      memoize def user_has_code_review_access?
        Copilot::Public::User.for(current_user).code_review_enabled?
      end

      memoize def copilot_memory_enabled?
        current_copilot_user && current_repository.adminable_by?(current_user) && FeatureFlag.vexi.enabled?("copilot_memory_enablement_policy", current_user, default: false) &&
          Copilot::Policies::Memory.effective_value(current_copilot_user) == "enabled"
      end

      memoize def copilot_setup_steps_file_path
        nwo = current_repository.name_with_display_owner
        default_branch = current_repository.default_branch

        return nil if !default_branch || !current_user_can_push? || !current_repository.includes_directory?(".github/workflows", default_branch)

        if current_repository.includes_file?(COPILOT_SETUP_STEPS_PATH, default_branch)
          "/#{nwo}/edit/#{default_branch}/#{COPILOT_SETUP_STEPS_PATH}"
        else
          "/#{nwo}/new/#{default_branch}/.github/workflows?filename=copilot-setup-steps.yml"
        end
      end

      memoize def copilot_coding_agent_enabled?
        current_repository.adminable_by?(current_user) &&
          current_repository.owner.copilot_swe_agent_enabled_for?(current_repository)
      end

      memoize def copilot_coding_agent_enabled_for_repo?
        current_repository.owner.copilot_swe_agent_enabled_for?(current_repository)
      end

      memoize def has_agents_md?
        default_branch = current_repository.default_branch
        return false unless default_branch

        current_repository.includes_file?(".github/agents.md", default_branch) ||
          current_repository.includes_file?(".github/copilot-instructions.md", default_branch)
      end

      memoize def has_paid_copilot_access?
        copilot_user = current_copilot_user
        return false unless copilot_user

        copilot_user.has_paid_access?
      end

      memoize def has_ce_or_cb_access?
        copilot_user = current_copilot_user
        return false unless copilot_user

        copilot_user.has_ce_access? || copilot_user.has_cb_access?
      end

      memoize def steering_enabled?
        Copilot::Public::User.for(current_user).has_copilot_access?
      end

      memoize def can_create_tasks?
        current_user_can_push?
      end

      memoize def use_token_based_billing?
        Copilot::Public::User.for(current_user).use_token_based_billing?
      end

      # Fetches the current user's quota snapshot from the limiter client.
      sig { params(user: User).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def agent_quota_snapshot_for_user(user)
        Copilot::Users::AgentQuotaSnapshot.new.build(user: user)
      end

      def task_head_ref(task)
        return nil unless task

        branch_artifact = task.artifacts.find do |artifact|
          artifact["provider"] == "github" &&
            artifact["type"] == "branch"
        end

        branch_artifact&.dig("data", "head_ref")
      end

      def log_capi_error(source, error)
        GitHub.logger.error(
          "copilot_agents_controller CAPI error",
          {
            "gh.copilot_coding_agent.error_source" => source,
            "gh.copilot_coding_agent.error_class" => error.class.name,
            "gh.copilot_coding_agent.error_message" => error.message.to_s.truncate(500),
            "gh.copilot_coding_agent.task_id" => params[:task_id],
            "gh.copilot_coding_agent.pull_number" => params[:pull_number],
            "gh.copilot_coding_agent.session_id" => params[:session_id],
            "gh.user.id" => current_user&.id,
            "gh.repo.id" => current_repository.id,
            "gh.request_id" => GitHub.context[:request_id],
          }
        )
        GitHub.dogstats.increment(
          "copilot_agents_controller.capi_error",
          tags: [
            "source:#{source}",
            "error_class:#{error.class.name}",
          ]
        )
      end

      # Shared pipeline that both PullTasksController and TasksController call
      # after obtaining initial sessions. Handles experiment exposure, focused
      # session fallback, empty-sessions 404, and payload construction.
      #
      # Returns { title:, payload:, task_id: } or nil (already rendered 404).
      def prepare_task_response(sessions:, pull:, task:, route_id:, token:, task_id: nil)
        user = T.must(current_user)

        # Experiment exposure
        emit_experiment_exposure(
          surface_type: :AGENT_SURFACE_TYPE_MISSION_CONTROL,
          entry_point: "repo_agents_task",
          session_id: params[:session_id],
        )

        # Focused session fallback — when session_id param is present but not
        # found in the initial sessions list, fetch it directly.
        focused_session_id = params[:session_id]
        if focused_session_id.present? && focused_session_id !~ /\A[a-zA-Z0-9\-_]+\z/
          render_404
          return nil
        end
        param_session_missing = sessions.none? { |session| session.id == focused_session_id }

        if (sessions.empty? || param_session_missing) && focused_session_id.present?
          begin
            session = CopilotSessions::AgentSession.for_session(
              user:,
              session_id: focused_session_id,
              user_session:,
              token:
            )
            sessions = [session].compact
          rescue CopilotAPI::UnauthorizedError => e
            unless FeatureFlag.vexi.enabled?(:copilot_mission_control_initial_data_spinner, current_user, default: false)
              raise
            end
            log_capi_error("task.for_session", e)
          end
        end

        # Empty sessions guard
        if sessions.empty? && !FeatureFlag.vexi.enabled?(:copilot_mission_control_initial_data_spinner, current_user, default: false)
          render_404
          return nil
        end

        task_id ||= task&.id || sessions.first&.task_id
        title = pull ? "Agents · #{pull.title}" : "Agents · #{current_repository.name_with_display_owner}"

        branch_name = task_head_ref(task) || pull&.display_head_ref_name
        branch_alive_channel = branch_name ? GitHub::WebSocket::Channels.signed_branch(current_repository, branch_name) : nil

        payload = Repos::Agents::TaskPayload.new(
          pull,
          repo_data,
          user,
          can_create_tasks?,
          steering_enabled?,
          use_token_based_billing?,
          sessions,
          route_id: route_id,
          branch_alive_channel: branch_alive_channel,
          task_id: task_id,
          task: task,
          token: token,
          sso_org_ids: saml_for_user.protected_organization_ids.map(&:to_s),
          user_has_code_review_access: user_has_code_review_access?,
          agent_quota_snapshot: agent_quota_snapshot_for_user(user),
          remote_control_policy_enabled: Copilot::Public::User.for(current_user).cli_remote_control_enabled?,
          automations_visible_for_current_user: automations_visible_for_current_user?,
        )

        { title: title, payload: payload, task_id: task_id }
      end

      memoize def automations_enabled?
        enabled_for_user = current_user&.feature_flag_enabled?(:copilot_swe_agent_custom_agent_triggers, default: false)
        enabled_for_repository = current_repository&.feature_flag_enabled?(:copilot_swe_agent_custom_agent_triggers, default: false)
        enabled_for_user && enabled_for_repository
      end

      # Whether the Automations area of the repo-agents app should be visible to
      # the current user. AND of the triggers FF, the repository-visibility
      # check (public repos excluded), the automations-disabled kill switch,
      # and the effective org+repo read-access-triggers policy.
      memoize def automations_visible_for_current_user?
        return false unless automations_enabled?
        return false if block_public_repos_for_automations?
        return false if current_repository.copilot_swe_agent_automations_disabled?
        return true if current_user_can_push?

        effective_allow_read_access_triggers?
      end

      memoize def block_public_repos_for_automations?
        current_repository.public? &&
          current_repository.feature_flag_enabled?(:copilot_automations_block_public_repos, default: true)
      end

      # Org-level read-access policy, or nil for user-owned repos (no org policy applies).
      memoize def org_allow_read_access_triggers_policy
        owner = current_repository.owner
        owner.is_a?(::Organization) ? owner.copilot_swe_agent_allow_read_access_triggers_policy : nil
      end

      memoize def repo_allow_read_access_triggers_policy
        current_repository.copilot_swe_agent_repo_allow_read_access_triggers_policy
      end

      # `org_allows && repo_allows` — mirrors the Twirp `GetEffectiveTriggerActorPolicy`
      # handler that sweagentd consults at trigger time, so UI and runtime agree.
      memoize def effective_allow_read_access_triggers?
        org_allow_read_access_triggers_policy != false && repo_allow_read_access_triggers_policy
      end
    end
  end
end
