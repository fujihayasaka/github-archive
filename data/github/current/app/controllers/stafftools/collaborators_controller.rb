# typed: true
# frozen_string_literal: true

class Stafftools::CollaboratorsController < StafftoolsController

  before_action :ensure_repo_exists
  before_action :redirect_if_org_owned

  layout "layouts/stafftools/repository/security"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Spokes,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  def index
    query = [
      "repo_id:#{current_repository.id}",
      "action:(repository_invitation.* OR repo.*_member)",
    ].join(" ")

    if GitHub.driftwood_ade_queries_enabled?
      query = <<~KQL
        webevents
        | where repo_id == #{current_repository.id}
        | where (action startswith "repository_invitation." or action in ("repo.add_member", "repo.remove_member", "repo.update_member"))
      KQL
    end


    fetch_audit_log_teaser query

    collaborators = current_repository.members.order("login ASC")
      .paginate(page: current_page)

    invites = if current_page == 1
      current_repository.repository_invitations.includes(:invitee)
    else
      []
    end

    render "stafftools/collaborators/index", locals: {
      query: @query,
      more_results: @more_results,
      logs: @logs,
      collaborators: collaborators,
      invites: invites
    }
  end

  private

  def redirect_if_org_owned
    if current_repository.organization
      redirect_to gh_permissions_stafftools_repository_path(current_repository)
    end
  end
end
