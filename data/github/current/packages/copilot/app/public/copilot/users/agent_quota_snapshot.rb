# typed: strict
# frozen_string_literal: true

module Copilot
  module Users
    class AgentQuotaSnapshot
      include Api::Internal::Twirp::Copilot::Helpers

      # Session AIC median threshold consumed per job when token-based billing is enabled.
      # Used as the threshold for whether an individual user has enough quota to run a job.
      # Source dashboard:
      # https://dataexplorer.azure.com/dashboards/10c783cc-d1e2-4c34-9e11-a9f8061c8482?p-_startTime=90days&p-_endTime=now#4643696b-94f9-40f1-8538-f7936efbf01e
      SESSION_AIC_MEDIAN_THRESHOLD = 45

      AgentQuotaSnapshotPayload = T.type_alias do
        T::Hash[Symbol, T.any(Integer, Float, T::Boolean, String, NilClass)]
      end

      sig { params(user: ::User).returns(T.nilable(AgentQuotaSnapshotPayload)) }
      def build(user:)
        return nil unless user.feature_flag_enabled?(:copilot_coding_agent_tbb_quota_banner, default: false)

        copilot_user = Copilot::User.new(user)

        # Users without Copilot access (e.g. :NO_ACCESS) have no quota to query.
        # Skip the limiter RPC to avoid a wasted call that always fails with invalid_sku.
        return nil unless copilot_user.has_copilot_access?

        # Check if user is on token-based billing
        return nil unless copilot_user.use_token_based_billing?

        quota_remaining = CopilotLimiter::Twirp.quota_client.get_quota_remaining(
          copilot_tracking_id: user.analytics_tracking_id,
          twirp_access_type: twirp_access_type(copilot_user.access_type),
          interaction_id: GitHub.context[:request_id],
        )

        # Check if limiter returned quota in AIC
        return nil unless quota_remaining.token_based_billing?

        # Check if premium interactions quota details are present
        premium_interactions_quota_details = quota_remaining.quota_details[:premium_interactions]
        return nil if premium_interactions_quota_details.nil?

        copilot_plan = copilot_user.copilot_plan

        {
          percent_remaining: premium_interactions_quota_details[:percent_remaining],
          can_start_session: can_start_session?(copilot_plan: copilot_plan, quota_details: premium_interactions_quota_details),
          can_upgrade_plan: copilot_user.can_upgrade_plan?,
          copilot_plan: copilot_plan,
          overage_permitted: overage_permitted?(copilot_plan: copilot_plan, quota_details: premium_interactions_quota_details),
          quota_reset_date: copilot_user.quota_reset_date.to_s,
        }
      end

      private

      sig do
        params(
          copilot_plan: String,
          quota_details: CopilotLimiter::Twirp::QuotaClient::UserQuotaRemaining,
        ).returns(T::Boolean)
      end
      def can_start_session?(copilot_plan:, quota_details:)
        # For CE / CB, use has_quota to determine if user can start session
        # only CE / CB have has_quota field. They have 0 remaining and quota_remaining
        # If has_quota is nil (not present in response), fail open.
        if copilot_plan == "business" || copilot_plan == "enterprise"
          return true if quota_details[:has_quota].nil?
          return quota_details[:has_quota] == true
        end

        # For individual users, require a minimum amount of remaining quota to start a session, or overage is permitted
        # If remaining is nil (not present in response) and overage_permitted is nil, fail open.
        return true if quota_details[:remaining].nil? && quota_details[:overage_permitted].nil?
        remaining = quota_details[:remaining] || 0
        remaining > SESSION_AIC_MEDIAN_THRESHOLD || quota_details[:overage_permitted] == true
      rescue StandardError
        # In case of any error determining if the user can start a session, fail open
        true
      end

      sig do
        params(
          copilot_plan: String,
          quota_details: CopilotLimiter::Twirp::QuotaClient::UserQuotaRemaining,
        ).returns(T::Boolean)
      end
      def overage_permitted?(copilot_plan:, quota_details:)
        # overage_permitted is only meaningful for CFI (Copilot for Individuals)
        # users — they pay their own bill and can self-serve enabling/disabling
        # additional usage. For CB/CE users, blocking is driven by plan + trust
        # tier (`has_quota`) and unblock is by upgrade; the limiter's
        # overage_permitted field does not apply. See cfi-ux-guidance.md and
        # tbb-client-integration-guide.md.
        return false if copilot_plan == "business" || copilot_plan == "enterprise"

        quota_details[:overage_permitted] == true
      rescue StandardError
        false
      end
    end
  end
end
