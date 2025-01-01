# typed: true
# frozen_string_literal: true

class Orgs::SecurityCenter::AbstractSecurityCampaignsController < Orgs::SecurityCenter::AbstractSecurityCenterController
  before_action :login_required
  before_action :security_center_required
  before_action :security_campaigns_required

  skip_before_action :set_failbot_context

  private

  sig { params(number: T.untyped).returns(T.nilable(SecurityCampaigns::SecurityCampaign)) }
  def find_security_campaign(number:)
    campaign = SecurityCampaigns::SecurityCampaign.find_by(number:, organization: this_organization.id)
    return nil if campaign.nil?

    # Allow security managers/owners to access all campaigns
    return campaign if SecurityProduct::Permissions::OrgAuthz.new(this_organization, actor: current_user).can_manage_security_products?

    # Do not allow developers to access closed campaigns
    return nil if campaign.closed?

    has_access_to_repository_in_campaign = this_organization.repositories.active.where(id: campaign.security_campaign_alerts.distinct.pluck(:repository_id)).any? do |repository|
      repository.code_scanning_readable_by?(current_user)
    end

    # Only allow access to this campaign if the developer has access to at least one repository in the campaign
    return nil unless has_access_to_repository_in_campaign

    campaign
  end

  def security_campaigns_required
    render_404 unless SecurityCampaigns.enabled?(this_organization)
  end
end
