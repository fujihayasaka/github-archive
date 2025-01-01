# typed: true
# frozen_string_literal: true

class Forks::ForksController < GitContentController
  include Forks::ForksControllerDependency
  include Forks::PaginatedForksDependency
  extend T::Sig

  # We don't need these two before_actions here,
  # but the rest of the parent class is helpful for
  # setting up the repo view layout.
  skip_before_action :ask_the_gitkeeper
  skip_before_action :try_to_expand_path
  before_action :require_repository, only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  layout "repository"
  stylesheet_bundle :insights
  javascript_bundle :forks

  def index
    forks = paginated_forks_for(
      repository: T.must(current_repository),
      actor: current_user,
      options: safe_options_resolver,
    ).to_a
    root_repo_has_forks = @attribute_resolver.ids_by_owner_login.any? || @base_scope.exists?
    repo = T.must(current_repository)
    path_resolver = Forks::PathResolver.new(
      repo.name,
      repo.owner_display_login,
      safe_options_resolver,
    )

    render "forks/index", locals: {
      forks:,
      root_repo_has_forks:,
      attributes: @attribute_resolver.resolve,
      path_resolver: path_resolver
    }
  end

  private

  def require_repository
    render_404 unless current_repository
  end
end
