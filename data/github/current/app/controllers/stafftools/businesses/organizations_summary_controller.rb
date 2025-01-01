# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::OrganizationsSummaryController < Stafftools::Businesses::BusinessBaseController
  skip_before_action :dotcom_required
  before_action :check_for_owners

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  def index
    render "stafftools/businesses/organizations/summary", locals: {
      member_org_count: this_business.organizations.count,
      created_org_invitation_count: \
        this_business.organization_invitations.with_status(:created).count,
      accepted_org_invitation_count: \
        this_business.organization_invitations.with_status(:accepted).count,
      confirmed_org_invitation_count: \
        this_business.organization_invitations.with_status(:confirmed).count,
      initiated_organization_transfers_count: \
        BusinessOrganizationTransfer.where(from_business: this_business).count,
      received_organization_transfers_count: \
        BusinessOrganizationTransfer.where(to_business: this_business).count,
      deleted_member_org_count: \
        ::Organization.where(id: this_business.soft_deleted_organization_ids).count,
    }
  end
end
