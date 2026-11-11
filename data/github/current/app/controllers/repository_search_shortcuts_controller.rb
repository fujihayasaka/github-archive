# typed: strict
# frozen_string_literal: true

class RepositorySearchShortcutsController < AbstractRepositoryController
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency
  include IssuesReactHelper

  UPDATABLE_FIELDS = %i[name description icon color query].freeze

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = T.let([
    "RepositorySearchShortcutsController#create",
    "RepositorySearchShortcutsController#update",
    "RepositorySearchShortcutsController#destroy",
  ].freeze, T::Array[String])

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Profiles,
    ApplicationRecord::Repositories,
    optional: false

  depends_on_clusters ApplicationRecord::Copilot,
    ApplicationRecord::Spokes,
    optional: true

  allow_verified_fetch only: %w(create update destroy)

  before_action :require_pinned_views_feature
  before_action :require_pinned_views_index_page, only: %i[index new]
  before_action :try_parse_json_params, only: %i[create update]
  before_action :require_triage_permissions, only: %i[create update destroy]
  before_action :find_shortcut, only: %i[show update destroy]

  SORT_OPTIONS = T.let({
    "recently_updated" => { updated_at: :desc },
    "newest" => { created_at: :desc },
    "oldest" => { created_at: :asc },
    "least_recently_updated" => { updated_at: :asc },
    "name" => { name: :asc },
  }.freeze, T::Hash[String, T::Hash[Symbol, Symbol]])

  sig { void }
  def index
    respond_to do |format|
      format.html { render_issues_react }
      format.json do
        sort = SORT_OPTIONS[params[:sort]] || SORT_OPTIONS["recently_updated"]
        shortcuts = issues_shortcuts_scope.order(sort)
        render json: { savedViews: shortcuts.map { |s| shortcut_payload(s) } }
      end
    end
  end

  sig { void }
  def show
    respond_to do |format|
      format.html { render_issues_react }
      format.json do
        render json: { savedView: shortcut_payload(T.must(@shortcut)) }
      end
    end
  end

  sig { void }
  def new
    render_issues_react
  end

  sig { void }
  def create
    shortcut = RepositorySearchShortcut.create!(
      **params.slice(*UPDATABLE_FIELDS).permit(*UPDATABLE_FIELDS),
      repository: current_repository,
      creator: current_user,
      search_type: :issues,
      creation_source: params[:source],
    )

    render json: { savedView: shortcut_payload(shortcut) }, status: :created
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    render_error(e.message, :bad_request)
  end

  sig { void }
  def update
    update_params = params.slice(*UPDATABLE_FIELDS).permit(*UPDATABLE_FIELDS)

    shortcut = T.must(@shortcut)
    shortcut.acting_user = current_user
    shortcut.update!(update_params)
    render json: { savedView: shortcut_payload(shortcut) }
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    render_error(e.message, :bad_request)
  end

  sig { void }
  def destroy
    shortcut = T.must(@shortcut)
    shortcut.acting_user = current_user
    shortcut.destroy!
    head :ok
  end

  private

  sig { params(shortcut: RepositorySearchShortcut).returns(T::Hash[Symbol, T.untyped]) }
  def shortcut_payload(shortcut)
    {
      id: shortcut.id,
      name: shortcut.name,
      description: shortcut.description,
      icon: shortcut.icon,
      color: shortcut.color,
      query: shortcut.query,
      position: shortcut.priority,
      createdAt: shortcut.created_at&.iso8601,
      updatedAt: shortcut.updated_at&.iso8601,
      creatorLogin: shortcut.creator&.display_login,
    }
  end

  sig { void }
  def require_pinned_views_feature
    render_404 unless PinnedViewsFeature.enabled?(current_repository, actor: current_user)
  end

  sig { void }
  def require_pinned_views_index_page
    return if PinnedViewsFeature.index_page_enabled?(current_repository, actor: current_user)

    respond_to do |format|
      format.html { redirect_to "/#{current_repository.name_with_display_owner}/issues/created_by/views" }
      format.json { render_404 }
    end
  end

  sig { void }
  def require_triage_permissions
    unless Issue::PermissionsDependency.repo_triageable_by?(current_user, current_repository)
      render_error("You need triage permissions to manage views", :forbidden)
    end
  end

  sig { returns(ActiveRecord::Relation) }
  def issues_shortcuts_scope
    RepositorySearchShortcut.issues_search_type.includes(:creator).where(repository: current_repository)
  end

  sig { void }
  def find_shortcut
    @shortcut = T.let(
      issues_shortcuts_scope.find_by(id: params[:id]),
      T.nilable(RepositorySearchShortcut),
    )
    render_404 unless @shortcut
  end

  sig { params(message: String, status: Symbol).void }
  def render_error(message, status)
    render json: { error: { message: message } }, status: status
  end

  sig { void }
  def render_issues_react
    @repository_search_shortcut = T.let(@shortcut, T.nilable(RepositorySearchShortcut)) if @shortcut
    issue_react_index_handler
  end
end
