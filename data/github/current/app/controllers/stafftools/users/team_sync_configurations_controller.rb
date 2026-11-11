# typed: true
# frozen_string_literal: true

class Stafftools::Users::TeamSyncConfigurationsController < StafftoolsController
  before_action :ensure_org_not_user
  before_action :ensure_user_exists

  def create
    UpdateTeamSyncForBusinessOrganizationJob.perform_later(org_id: this_user.id)

    redirect_to(
      stafftools_user_security_path(this_user),
      notice: "Scheduled configuration for #{this_user} to match enterprise configuration.",
    )
  end
end
