# typed: strict
# frozen_string_literal: true

class Orgs::SecurityCenter::SecurityCampaignsCountsController < Orgs::SecurityCenter::AbstractSecurityCampaignsController
  include Orgs::SecurityCenter::CodeScanningOrgQueriesHelper

  before_action :organization_read_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Notify,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Spokes,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    only: [:index]

  sig { void }
  def index
    return render_404 if !SecurityCampaigns.enabled?(this_organization)

    can_manage_security_products = SecurityProduct::Permissions::OrgAuthz.new(this_organization, actor: current_user).can_manage_security_products?

    visible_campaign_counts = SecurityCampaigns::VisibleCampaignsCountsService.call(
      user: current_user,
      org: this_organization,
      allowed_repository_ids: allowed_repo_ids_and_limit_exceeded&.first,
      can_manage_security_products:
    )

    render json: visible_campaign_counts.to_react_payload
  end

  # Unfortunately this method is overwriten in the AbstractSecurityCenterController. We need the initial
  # implementation and have to call the the abstracts parent controller method to do so.
  sig { returns(T.untyped) }
  def params # rubocop:todo GitHub/UseRestfulActions
    Orgs::Controller.instance_method(:params).bind(self).call
  end
end
