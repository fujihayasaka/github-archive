# typed: true
# frozen_string_literal: true

class Orgs::Invitations::ReinstatedStatusController < Orgs::Controller
  include Orgs::InvitationsControllerMethods

  before_action :login_required

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot, only: [:show], optional: true

  def show
    restorable_organization_user = Restorable::OrganizationUser.restorable(this_organization, current_user)
    status = restorable_organization_user.job_status
    if status
      render "orgs/invitations/reinstate_status", locals: {
        organization: this_organization,
        status: status,
        continue_path: reinstate_return_to_path,
      }
    else
      redirect_to user_path(this_organization)
    end
  end
end
