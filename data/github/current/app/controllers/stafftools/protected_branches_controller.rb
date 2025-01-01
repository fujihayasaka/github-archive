# typed: true
# frozen_string_literal: true

class Stafftools::ProtectedBranchesController < StafftoolsController # rubocop:todo GitHub/ControllersShouldHaveTests
  before_action :ensure_repo_exists

  layout "layouts/stafftools/repository/security"

  def index
    branches = current_repository.protected_branches
    audit_query = "repo_id:#{current_repository.id} (action:protected_branch*.* OR action:required_status_check.*)"

    if GitHub.driftwood_ade_queries_enabled?
      audit_query = <<~KQL
        webevents
        | where repo_id == #{current_repository.id}
        | where action startswith "protected_branch." or action startswith "required_status_check."
      KQL
    end

    render "stafftools/protected_branches/index", locals: { branches: branches, audit_query: audit_query }
  end
end
