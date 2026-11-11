# typed: strict
# frozen_string_literal: true

class Repos::BranchProtections::ReadOnlyController < AbstractRepositoryController
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency

  include Repos::BranchProtections::Concerns::Structs
  include Repos::BranchProtections::Concerns::ReactPayload
  include Repos::BranchProtections::Concerns::Hooks

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    only: [:index, :show]

  depends_on_clusters ApplicationRecord::Copilot,
    optional: true

  before_action :ensure_read_only_enabled
  before_action :login_required
  before_action :ensure_plan_supports_rules

  layout "layouts/repository_with_container"

  sig { returns(String) }
  def self.react_bundle_name
    "branch-protections-read-only"
  end

  sig { void }
  def index
    respond_with_react(
      payload: IndexRoutePayload.new(protected_branches: current_repository.protected_branches.to_a),
      nested_payloads: -> { [LayoutRoutePayload.new] },
      title: "Branch Protections",
      page_data: {
        selected_link: :repo_source,
      },
    )
  end

  sig { void }
  def show
    protected_branch = ::ProtectedBranch.find_by(id: params.require(:id), repository: current_repository)
    return render_404 unless protected_branch.present?

    respond_with_react(
      payload: ShowRoutePayload.new(protected_branch:),
      nested_payloads: -> { [LayoutRoutePayload.new] },
      title: "Branch Protections · #{protected_branch.name}",
      page_data: {
        selected_link: :repo_source,
      },
    )
  end
end
