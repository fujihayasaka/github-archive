# typed: strict
# frozen_string_literal: true

# Fetches visible counts for campaigns
# Developers can see draft campaigns even if they don't have access to alerts in the campaign
# If the user is not security manager, then we do not show any statistics
module SecurityCampaigns
  class VisibleCampaignsCountsService
    include GitHub::Memoizer

    sig { params(user: User, org: Organization, allowed_repository_ids: T.nilable(T::Array[Integer]), can_manage_security_products: T::Boolean, alert_type: String).void }
    def initialize(user:, org:, allowed_repository_ids:, can_manage_security_products:, alert_type:)
      @user = user
      @org = org
      @allowed_repository_ids = allowed_repository_ids
      @can_manage_security_products = can_manage_security_products
      @alert_type = alert_type
    end
    private_class_method :new

    sig { params(user: User, org: Organization, allowed_repository_ids: T.nilable(T::Array[Integer]), can_manage_security_products: T::Boolean, alert_type: String).returns(VisibleCampaignsCounts) }
    def self.call(user:, org:, allowed_repository_ids:, can_manage_security_products:, alert_type:)
      new(user:, org:, allowed_repository_ids:, can_manage_security_products:, alert_type:).call
    end

    sig { returns(VisibleCampaignsCounts) }
    def call
      open_campaigns_open_count = alert_counts_for_open_campaigns&.open_count || 0
      open_campaigns_closed_count = alert_counts_for_open_campaigns&.closed_count || 0
      open_campaigns_in_progress_count = alert_counts_for_open_campaigns&.open_with_links_count || 0
      open_campaigns_dismissed_count = alert_counts_for_open_campaigns&.dismissed_count || 0
      open_campaigns_autofix_generated_count = alert_counts_for_open_campaigns&.autofix_generated_count || 0

      open_campaigns_autofix_accepted_count = alert_counts_for_open_campaigns&.autofix_accepted_count || 0
      closed_campaigns_open_count = alert_counts_for_closed_campaigns&.open_count || 0
      closed_campaigns_closed_count = alert_counts_for_closed_campaigns&.closed_count || 0
      closed_campaigns_dismissed_count = alert_counts_for_closed_campaigns&.dismissed_count || 0
      closed_campaigns_autofix_generated_count = alert_counts_for_closed_campaigns&.autofix_generated_count || 0
      closed_campaigns_autofix_accepted_count = alert_counts_for_closed_campaigns&.autofix_accepted_count || 0

      VisibleCampaignsCounts.new(
        open_campaigns_count:,
        closed_campaigns_count:,
        draft_campaigns_count: draft_campaigns_without_spam.count,
        open_campaigns_total_count: open_campaigns_open_count + open_campaigns_closed_count,
        open_campaigns_open_count: open_campaigns_open_count,
        open_campaigns_in_progress_count: open_campaigns_in_progress_count,
        open_campaigns_fixed_count: open_campaigns_closed_count - open_campaigns_dismissed_count,
        open_campaigns_dismissed_count: open_campaigns_dismissed_count,
        closed_campaigns_total_count: closed_campaigns_open_count + closed_campaigns_closed_count,
        closed_campaigns_open_count: closed_campaigns_open_count,
        closed_campaigns_fixed_count: closed_campaigns_closed_count - closed_campaigns_dismissed_count,
        closed_campaigns_dismissed_count: closed_campaigns_dismissed_count,
        autofix_generated_count: open_campaigns_autofix_generated_count + closed_campaigns_autofix_generated_count,
        autofix_applied_count: open_campaigns_autofix_accepted_count + closed_campaigns_autofix_accepted_count,
        open_campaigns_count_with_spam: all_open_campaigns.size,
        draft_campaigns_count_with_spam: all_draft_campaigns.size,
        has_open_spam: has_open_spam?,
        has_draft_spam: has_draft_spam?,
      )
    end

    private

    sig { returns(T::Array[SecurityCampaigns::SecurityCampaign]) }
    def draft_campaigns_without_spam
      all_draft_campaigns.reject { |campaign| campaign.hide_from_user?(@user) }
    end

    sig { returns(T::Array[SecurityCampaigns::SecurityCampaign]) }
    memoize def all_draft_campaigns
      if FeatureFlag.vexi.enabled?(:secret_scanning_campaigns, @user, @org, @org.business, default: false)
        return SecurityCampaigns::SecurityCampaign.where(organization_id: @org.id).draft.for_alert_type(@alert_type).to_a
      end

      SecurityCampaigns::SecurityCampaign.where(organization_id: @org.id).draft.to_a
    end

    sig { returns(Integer) }
    memoize def closed_campaigns_count
      # For closed campaigns we just need the count because we get data by excluding the open campaigns
      return 0 unless @can_manage_security_products

      scope = SecurityCampaigns::SecurityCampaign.where(organization_id: @org.id)
      scope = scope.filter_spam_for(@user)

      if FeatureFlag.vexi.enabled?(:secret_scanning_campaigns, @user, @org, @org.business, default: false)
        return scope.closed.for_alert_type(@alert_type).count
      end

      scope.closed.count
    end

    sig { returns(Integer) }
    memoize def open_campaigns_count
      # Security managers can see all open campaigns
      return open_campaign_without_spam_ids.size if @can_manage_security_products

      # Find the allowed repositories for the user
      query_service = CodeScanning::AlertQueryService.for_organization(
        user: @user,
        user_session: nil,
        organization: @org,
        security_campaign_ids: open_campaign_without_spam_ids,
        allowed_repository_ids: @allowed_repository_ids
      )
      visible_open_campaigns = SecurityCampaigns::CampaignWithCounts.load(
        security_campaigns: open_campaigns_without_spam, query_service:
      ).filter do |campaign_with_counts|
        # filter out campaign with 0 counts
        campaign_with_counts.total_count.positive?
      end
      visible_open_campaigns.size
    end

    sig { returns(T::Array[SecurityCampaigns::SecurityCampaign]) }
    memoize def open_campaigns_without_spam
      all_open_campaigns.reject { |campaign| campaign.hide_from_user?(@user) }
    end

    sig { returns(T::Array[SecurityCampaigns::SecurityCampaign]) }
    memoize def all_open_campaigns
      if FeatureFlag.vexi.enabled?(:secret_scanning_campaigns, @user, @org, @org.business, default: false)
        return SecurityCampaigns::SecurityCampaign.where(organization_id: @org.id).open.for_alert_type(@alert_type).to_a
      end

      SecurityCampaigns::SecurityCampaign.where(organization_id: @org.id).open.to_a
    end

    sig { returns(T::Array[Integer]) }
    memoize def open_campaign_without_spam_ids
      open_campaigns_without_spam.map(&:id).sort
    end

    sig { returns(T::Array[SecurityCampaigns::SecurityCampaign]) }
    memoize def closed_campaigns_without_spam
      all_closed_campaigns.reject { |campaign| campaign.hide_from_user?(@user) }
    end

    sig { returns(T::Array[SecurityCampaigns::SecurityCampaign]) }
    memoize def all_closed_campaigns
      if FeatureFlag.vexi.enabled?(:secret_scanning_campaigns, @user, @org, default: false)
        return SecurityCampaigns::SecurityCampaign.where(organization_id: @org.id).closed.for_alert_type(@alert_type).to_a
      end

      SecurityCampaigns::SecurityCampaign.where(organization_id: @org.id).closed.to_a
    end

    sig { returns(T::Array[Integer]) }
    memoize def closed_campaign_without_spam_ids
      closed_campaigns_without_spam.map(&:id).sort
    end

    sig { returns(T.nilable(Turboscan::Proto::TotalCountsForCampaignsResponse)) }
    memoize def alert_counts_for_open_campaigns
      return unless @can_manage_security_products

      return if open_campaign_without_spam_ids.empty?

      # Fetch the data for open campaigns
      if FeatureFlag.vexi.enabled?(:secret_scanning_campaigns, @user, @org, default: false)
        if @alert_type == "secret_scanning"
          open_campaigns_query_service = SecretScanning::AlertQueryService.for_organization(
            organization: @org,
            current_user: @user,
            user_session: nil,
            security_campaign_ids: open_campaign_without_spam_ids,
          )
          open_count, closed_count, error = open_campaigns_query_service.get_alert_counts(include_resolved: true)

          return nil if error.present?

          return Turboscan::Proto::TotalCountsForCampaignsResponse.new(
            open_count: open_count,
            closed_count: closed_count,
            dismissed_count: closed_count, # secret scanning doesn't distinguish dismissed vs fixed
            open_with_links_count: 0, # not applicable for secret scanning
            autofix_generated_count: 0, # not applicable for secret scanning
            autofix_accepted_count: 0, # not applicable for secret scanning
            autofix_supported_count: 0 # not applicable for secret scanning
          )
        end
      end

      open_campaigns_query_service = CodeScanning::AlertQueryService.for_organization(
        user: @user,
        user_session: nil,
        organization: @org,
        security_campaign_ids: open_campaign_without_spam_ids,
      )
      open_campaigns_response = open_campaigns_query_service.total_counts_for_campaigns

      open_campaigns_response&.data
    end

    sig { returns(T.nilable(Turboscan::Proto::TotalCountsForCampaignsResponse)) }
    memoize def alert_counts_for_closed_campaigns
      return unless @can_manage_security_products

      return if closed_campaigns_count.zero?

      if FeatureFlag.vexi.enabled?(:secret_scanning_campaigns, @user, @org, default: false)
        if @alert_type == "secret_scanning"
          return if closed_campaign_without_spam_ids.empty?

          closed_campaigns_query_service = SecretScanning::AlertQueryService.for_organization(
            organization: @org,
            current_user: @user,
            user_session: nil,
            security_campaign_ids: closed_campaign_without_spam_ids,
          )
          open_count, closed_count, error = closed_campaigns_query_service.get_alert_counts(include_resolved: true)

          return nil if error.present?

          return Turboscan::Proto::TotalCountsForCampaignsResponse.new(
            open_count: open_count,
            closed_count: closed_count,
            dismissed_count: closed_count, # secret scanning doesn't distinguish dismissed vs fixed
            open_with_links_count: 0, # not applicable for secret scanning
            autofix_generated_count: 0, # not applicable for secret scanning
            autofix_accepted_count: 0, # not applicable for secret scanning
            autofix_supported_count: 0 # not applicable for secret scanning
          )
        end
      end

      query_service = CodeScanning::AlertQueryService.for_organization(
        user: @user,
        user_session: nil,
        organization: @org,
        security_campaign_state: ::Turboscan::Proto::SecurityCampaignStateFilter.new(
          open_security_campaign_ids: open_campaign_without_spam_ids,
          # This could be simplified to include:closed,exclude:open, but that's less performant than using this filter.
          # This filter translates to has:security_campaign_ids AND excluded_security_campaign_ids: open_security_campaign_ids.
          # Using the alternative translates to a much more complex filter that will need to run an ElasticSearch
          # script in Turboscan.
          include: [::Turboscan::Proto::SecurityCampaignState::SECURITY_CAMPAIGN_STATE_OPEN, ::Turboscan::Proto::SecurityCampaignState::SECURITY_CAMPAIGN_STATE_CLOSED],
          exclude: [::Turboscan::Proto::SecurityCampaignState::SECURITY_CAMPAIGN_STATE_OPEN],
        ),
      )
      closed_campaigns_response = query_service.total_counts_for_campaigns
      closed_campaigns_response&.data
    end

    sig { returns(T::Boolean) }
    def has_open_spam?
      all_open_campaigns.any? do |campaign|
        campaign.hide_from_user?(@user)
      end
    end

    sig { returns(T::Boolean) }
    def has_draft_spam?
      all_draft_campaigns.any? do |campaign|
        campaign.hide_from_user?(@user)
      end
    end
  end
end
