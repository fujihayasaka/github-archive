# typed: true
# frozen_string_literal: true

module Navigation
  module Repository
    class SecurityView
      include GitHub::Memoizer
      include SecretScanning::Features::FeatureFlagHelper

      attr_reader :current_user, :current_repository

      sig { params(current_user: T.nilable(User), current_repository: ::Repository).void }
      def initialize(current_user:, current_repository:)
        @current_user = current_user
        @current_repository = current_repository
        @token_scanning = SecretScanning::Features::Repo::TokenScanning.new(current_repository)
        @delegated_bypass = SecretScanning::Features::Repo::DelegatedBypass.new(current_repository)
        @generic_secrets = SecretScanning::Features::Repo::GenericSecrets.new(current_repository)
        @lower_confidence_patterns = SecretScanning::Features::Repo::LowerConfidencePatterns.new(current_repository)
      end

      memoize def show_advisories?
        current_repository.advisories_enabled?
      end

      memoize def show_dependabot_alerts?
        current_repository.can_view_vulnerability_alerts?(current_user)
      end

      memoize def show_token_scanning?
        @token_scanning.view_alerts_allowed?(current_user)
      end

      memoize def show_bypass_requests?
        @delegated_bypass.can_view_requests_list?(current_user)
      end

      memoize def show_token_scanning_results?
        show_token_scanning? && @token_scanning.enabled?
      end

      memoize def show_code_quality?
        current_user && CodeQuality.enabled?(current_repository) &&
        CodeQualityRepositoryPermissions.new(current_repository).code_quality_readable_by?(current_user)
      end

      memoize def show_code_quality_recent_activity?
        CodeQuality.recent_activity_enabled?(current_repository)
      end

      memoize def show_code_scanning?
        current_repository.code_scanning_readable_by?(current_user)
      end

      memoize def show_security_campaigns?
        SecurityCampaigns.enabled?(current_repository.owner) &&
        current_repository.code_scanning_readable_by?(current_user) &&
        security_campaigns_with_counts.map(&:security_campaign).any?
      end

      memoize def show_advisory_count_only?
        !show_dependabot_alerts? && show_advisories? && !show_token_scanning? && !show_code_quality? && !show_code_scanning?
      end

      memoize def security_count
        (show_dependabot_alerts? ? security_network_alerts_count : 0) +
          (show_advisories? ? security_advisories_count : 0) +
          (show_token_scanning_results? ? security_token_scanning_count : 0) +
          (show_code_scanning? && security_code_scanning_count > 0 ? security_code_scanning_count : 0)
      end

      memoize def security_network_alerts_count
        return 0 unless current_repository.vulnerability_alerts_enabled?
        if dependabot_alerts_use_es?
          Search::Queries::DependabotAlertsEsQuery.new(phrase: "is:open",
            scope: current_repository,
            current_user:,
          ).count

        else
          RepositoryVulnerabilityAlert::UngroupedAlertQuery.new(repository: current_repository, state: :open).total_entries
        end
      end

      memoize def security_advisories_count
        current_repository.repository_advisories.published.count
      end

      memoize def security_campaigns_with_counts
        open_campaigns = SecurityCampaigns::SecurityCampaign.open.where(organization_id: current_repository.owner_id)
        open_campaigns = open_campaigns.filter_spam_for(current_user)
        campaigns = open_campaigns.order(created_at: :asc).to_a
        query_service = CodeScanning::AlertQueryService.for_organization(
          user: current_user,
          user_session: nil,
          organization: current_repository.owner,
          security_campaign_ids: campaigns.map(&:id),
          allowed_repository_ids: [current_repository.id],
        )
        SecurityCampaigns::CampaignWithCounts.for_repo_with_alerts(security_campaigns: campaigns, query_service:)
      end

      memoize def security_code_scanning_count
        count = current_repository.code_scanning_open_alerts_count
        count > 0 ? count : 0
      end

      memoize def security_bypass_requests_count
        current_repository.token_scanning_bypass_request_count
      end

      memoize def security_token_scanning_count
        count = current_repository.token_scanning_service_unresolved_alerts_count
        count > 0 ? count : 0
      end

      sig { returns(Integer) }
      memoize def security_token_scanning_count_default
        count = current_repository.token_scanning_service_load_unresolved_alerts_count_for_result_category(:default)
        count > 0 ? count : 0
      end

      sig { returns(Integer) }
      memoize def security_token_scanning_count_generic
        count = current_repository.token_scanning_service_load_unresolved_alerts_count_for_result_category(:generic)
        count > 0 ? count : 0
      end

      sig { returns(T::Boolean) }
      memoize def split_secret_scanning_count?
        @generic_secrets.feature_available? || @lower_confidence_patterns.feature_available?
      end

      sig { returns(T::Boolean) }
      memoize def dependabot_alerts_use_es?
        current_repository.feature_flag_enabled?(:dependabot_use_elasticsearch, default: false)
      end
    end
  end
end
