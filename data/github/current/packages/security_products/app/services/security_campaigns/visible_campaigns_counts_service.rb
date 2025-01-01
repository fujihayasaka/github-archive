# typed: strict
# frozen_string_literal: true

# Fetches visible counts for campaigns
# Developers can see draft campaigns even if they don't have access to alerts in the campaign
# If the user is not security manager, then we do not show any statistics
module SecurityCampaigns
  class VisibleCampaignsCountsService
    include GitHub::Memoizer

    sig { params(user: User, org: Organization, allowed_repository_ids: T.nilable(T::Array[Integer]), can_manage_security_products: T::Boolean).void }
    def initialize(user:, org:, allowed_repository_ids:, can_manage_security_products:)
      @user = user
      @org = org
      @allowed_repository_ids = allowed_repository_ids
      @can_manage_security_products = can_manage_security_products
    end
    private_class_method :new

    sig { params(user: User, org: Organization, allowed_repository_ids: T.nilable(T::Array[Integer]), can_manage_security_products: T::Boolean).returns(VisibleCampaignsCounts) }
    def self.call(user:, org:, allowed_repository_ids:, can_manage_security_products:)
      new(user:, org:, allowed_repository_ids:, can_manage_security_products:).call
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
        draft_campaigns_count:,
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
        autofix_applied_count: open_campaigns_autofix_accepted_count + closed_campaigns_autofix_accepted_count
      )
    end

    private

    sig { returns(Integer) }
    memoize def draft_campaigns_count
      # Developers can see draft campaigns even if they don't have access to alerts in the campaign
      SecurityCampaigns::SecurityCampaign.draft.where(organization_id: @org.id).count
    end

    sig { returns(Integer) }
    memoize def closed_campaigns_count
      # For closed campaigns we just need the count because we get data by excluding the open campaigns
      return 0 unless @can_manage_security_products

      SecurityCampaigns::SecurityCampaign.closed.where(organization_id: @org.id).count
    end

    sig { returns(Integer) }
    memoize def open_campaigns_count
      # Security managers can see all open campaigns
      return all_open_campaign_ids.size if @can_manage_security_products

      # Find the allowed repositories for the user
      query_service = CodeScanning::AlertQueryService.for_organization(
        user: @user,
        user_session: nil,
        organization: @org,
        security_campaign_ids: all_open_campaign_ids,
        allowed_repository_ids: @allowed_repository_ids
      )
      visible_open_campaigns = SecurityCampaigns::CampaignWithCounts.load(
        security_campaigns: all_open_campaigns, query_service:, user: @user
      ).filter do |campaign_with_counts|
        # filter out campaign with 0 counts
        campaign_with_counts.total_count.positive?
      end
      visible_open_campaigns.size
    end

    sig { returns(T::Array[SecurityCampaigns::SecurityCampaign]) }
    memoize def all_open_campaigns
      SecurityCampaigns::SecurityCampaign.open.where(organization_id: @org.id).to_a
    end

    sig { returns(T::Array[Integer]) }
    memoize def all_open_campaign_ids
      all_open_campaigns.map(&:id).sort
    end

    sig { returns(T.nilable(Turboscan::Proto::TotalCountsForCampaignsResponse)) }
    memoize def alert_counts_for_open_campaigns
      return unless @can_manage_security_products

      return if all_open_campaign_ids.empty?

      # Fetch the data for open campaigns
      open_campaigns_query_service = CodeScanning::AlertQueryService.for_organization(
        user: @user,
        user_session: nil,
        organization: @org,
        security_campaign_ids: all_open_campaign_ids,
      )
      open_campaigns_response = open_campaigns_query_service.total_counts_for_campaigns

      open_campaigns_response&.data
    end

    sig { returns(T.nilable(Turboscan::Proto::TotalCountsForCampaignsResponse)) }
    memoize def alert_counts_for_closed_campaigns
      return unless @can_manage_security_products

      return if closed_campaigns_count.zero?

      query_service = CodeScanning::AlertQueryService.for_organization(
        user: @user,
        user_session: nil,
        organization: @org,
        excluded_security_campaign_ids: all_open_campaign_ids,
        require_present_in_campaign: true,
      )
      closed_campaigns_response = query_service.total_counts_for_campaigns
      closed_campaigns_response&.data
    end
  end
end
