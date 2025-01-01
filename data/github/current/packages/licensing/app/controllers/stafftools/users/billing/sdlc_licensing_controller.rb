# typed: strict
# frozen_string_literal: true

class Stafftools::Users::Billing::SdlcLicensingController < Stafftools::Users::BillingController
  include ::Licensing::Licensify

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::IssuesPullRequests,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  sig { void }
  def index
    render "stafftools/billing/sdlc_licensing/index", locals: { user: this_user }
  end

  sig { void }
  def update
    sync_org_memberships_req = Licensify::Services::V1::SyncOrganizationMembershipsRequest.new(
      entityId: this_user.id,
      entityType: Licensify::Services::V1::SyncEntityType::SYNC_ENTITY_TYPE_ORGANIZATION,
    )
    sync_org_memberships_res = licensify_client.sync_organization_memberships(sync_org_memberships_req)
    if sync_org_memberships_res.error.present?
      flash[:error] = "There was an issue synchronizing org memberships - #{sync_org_memberships_res.error}"
    else
      flash[:notice] = "We're synchronizing your SDLC licenses. This may take a few minutes."
    end

    redirect_to :back
  end
end
