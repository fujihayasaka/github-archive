# typed: true
# frozen_string_literal: true

class AbstractRepositoryController < ApplicationController
  abstract!

  REPOSITORY_PAGE_FEATURES = [
    :custom_roles, # NavigationHelper#internal_show_config if logged_in?
    :show_spammy_issues_to_staff, # NavigationHelper#open_issue_count
    :active_job_skip_enqueue,
    :consolidate_open_issue_and_pr_counts,
  ].to_set.freeze

  preload_features REPOSITORY_PAGE_FEATURES

  include IRepositoryController
  include BlobHelper
  include CurrentRepositoryInteractionsHelper
  include RepositoryControllerMethods
  include StaleModelDetection
  include SurveyHelper

  before_action :authorization_required
  before_action :allowed_from_referrer_sanitization
  before_action :ensure_advisory_workspace_allowed
  before_action :set_repo_as_hovercard_subject

  stylesheet_bundle :repository

  rescue_from Git::Ref::UnresolveableCommit,  with: :render_404
  rescue_from GitRPC::RepositoryOffline, with: :render_repository_offline
  rescue_from GitRPC::InvalidRepository, with: :render_down_for_maintenance

  rescue_from GitRPC::BadObjectState, Repository::CorruptionDetected do |boom|
    Failbot.report_user_error(boom)
    render "repositories/states/broken"
  end

  rescue_from ActionView::TemplateError do |e|
    if cause = e.cause
      rescue_with_handler(cause) || raise
    end
  end

  protected

  def add_spamurai_form_signals
    GitHub.context.push(spamurai_form_signals: spamurai_form_signals)
  end

  private

  helper_method :owner, :tree_name, :qualified_tree_name, :commit_sha, :tree_sha,
    :subscription_status, :current_directory, :sidebar_tree_name

  # Deprecate: Do not use in views.
  helper_method :current_commit

  # Public: Gets the subscription status for the current user and entity.
  #
  # Returns a Newsies::Responses::Subscription.
  memoize def subscription_status
    if logged_in? && current_repository
      with_database_error_fallback(fallback: nil) do
        GitHub.newsies.subscription_status(current_user, current_repository)
      end
    end
  end

  def allowed_from_referrer_sanitization
    if GitHub.allow_cross_origin_referrer_leak? && current_repository.try(:public?)
      disable_referrer_policy
    end
  end

  # Some branches may have `/` in their name. This really screws with
  # our routing, people.
  #
  # This method gives us a :name and a :path based on the
  # branches in a repository.
  #
  # In other words:
  #   `fixes/new` may mean two separate things:
  #    a) branch `fixes`, path `new`
  #    b) branch `fixes/new`
  def set_path_and_name
    # Clear out database errors from past requests here. We want to know for this request if we hit any errors so we
    # can render a custom error page if we are missing crucial data. Errors will be added to database_errors through
    # calls to with_database_error_fallback.
    clear_database_errors
    return if @set_path_and_name
    @set_path_and_name = true

    return if params[:name].blank? || !params[:path].blank?
    return if current_repository.nil?

    with_database_error_fallback(fallback: nil) do
      branch, path, qualified_name = ref_sha_path_extractor.call(params[:name])
      # just leave the entire path in params[:name] if it didn't find anything,
      # as there seems to be some logic that might depend on this
      if branch
        # Set `branch` so we can distinguish when the `name` param is a user-given invalid
        # branch versus an existing branch.
        params[:branch] = branch

        params[:name] = branch
        params[:path] = path.split("/") if path
        params[:qualified_name] = qualified_name
      end
    end
  end

  # Build issue from request params.
  def build_issue(unsafe_params)
    issue_builder = Issue::Builder.new(current_user, current_repository)
    issue_builder.build(unsafe_params)
  end

  memoize def ref_sha_path_extractor
    GitHub::RefShaPathExtractor.new(current_repository)
  end

  memoize def tree_name
    (params[:name] if params[:name].present?) || current_repository.default_branch
  end

  memoize def qualified_tree_name
    params[:qualified_name] || "refs/heads/#{current_repository.default_branch}"
  end

  # sidebar_tree_name gets the tree name for any links in the repo-next sidebar.
  # Specifically, it's used by the "Download Zip" button.  It needs to be
  # overwritten in any controller that uses the name/path for its own purposes,
  # like the ReleasesController.
  alias sidebar_tree_name tree_name

  memoize def tree_sha
    current_commit.try(:tree_oid)
  end

  memoize def commit_sha
    current_repository.ref_to_sha(tree_name)
  end

  def authorized?
    current_repository && (current_repository.public? || logged_in?)
  end

  # Don't disclose private repo existence by returing 401.
  def access_denied
    render_404
    false
  end

  # When an anonymous user accesses a public repository to take some kind
  # of action, redirect them to login instead of giving them a 404. The 404
  # is to hide the existence of a repo which isn't necessary for a public one.
  def login_required_redirect_for_public_repo
    if !logged_in? && current_repository && current_repository.public?
      redirect_to_login(request.url)
    else
      login_required
    end
  end

  def current_commit
    return @current_commit if defined?(@current_commit)

    @current_commit = commit_sha.presence && Repositories.domain.commits.by_oid(repository: current_repository, commit_oid: commit_sha)
  rescue GitRPC::InvalidObject, GitRPC::BadObjectState, GitRPC::Timeout
    @current_commit = nil
  rescue GitRPC::ObjectMissing
    @current_commit = nil

    # ref points to a missing object, aka repository corruption.
    #
    # it's conceivable that this could be raised mistakenly if we had a bad deploy or
    # an operational problem that caused GitRPC::ObjectMissing to be raised when the
    # objects did in fact exist.
    if ref = current_repository.refs.find(tree_name)
      raise Repository::CorruptionDetected, "ref points at missing commit #{ref.target_oid}"
    end

    @current_commit
  end

  def current_directory
    @current_directory ||= current_repository.directory(tree_name, path_string)

  rescue BERTRPC::UserError => boom
    # we still want the page to display.  just hide the tree area and log the error.
    # see app/views/tree/show to see what happens when tree is nil.
    # have a fresh change of underpants nearby.
    #
    # TODO: Make the comment correct
    failbot boom unless Rails.env.development? || Rails.env.test?
  end

  helper_method :current_ref
  # What's the current ref name we're browsing? Branch name, tag name, or
  # commit sha.
  def current_ref
    tree_name
  end

  helper_method :latest_commit_comment_id
  # Grabs the latest commit comment id for a given repository. Useful for
  # caching blocks that include commit comment counts.
  #
  # Returns an Integer of the latest commit comment ID.
  def latest_commit_comment_id(repository = current_repository)
    return @latest_commit_comment_id if defined?(@latest_commit_comment_id)
    @latest_commit_comment_id = repository.commit_comments.maximum(:id)
  end

  def request_writes_to_git?
    params[:controller] == "edit_repositories" ||
      %w( edit save ).include?(params[:action])
  end

  helper_method :can_modify_commit_comment?
  def can_modify_commit_comment?(comment)
    return false unless logged_in?

    comment.user == current_user ||
     current_user_can_push? &&
     !comment.try(:reference?)
  end

  def can_modify_issue_comment?(comment)
    return false unless logged_in?

    authorization = ContentAuthorizer.authorize(current_user, :issue_comment, :delete, repo: current_repository, issue: comment.issue)
    comment_author = comment.user_id == current_user.id
    can_push = current_repository.owner_id == current_user.id || current_user_can_push?

    # The issue/repo are liberated! Users can delete comments if:
    # - they're the comment author
    # - they have push access to the repo
    return can_push || comment_author if authorization.authorized?

    # Either the issue or repo are in an invalid state for modifying comments
    # We forbid adding modifying comments in all scenarios *except issue lock*
    # Users with push access can modify comments on locked issues
    auth_errors = authorization.errors(fail_fast: true).map(&:symbolic_error_code)
    if auth_errors.include?(:locked) || auth_errors.include?(:archived)
      can_push
    else
      false
    end
  end

  def parsed_issues_query
    [[:is, "open"], [:is, "issue"]]
  end
  helper_method :parsed_issues_query

  def find_assignee(login)
    if (assignee = User.find_by_login(login)) && current_repository.pullable_by?(assignee)
      assignee
    end
  end

  helper_method :blocked_by_owner?
  memoize def blocked_by_owner?
    current_repository&.owner_blocking?(current_user)
  end

  helper_method :current_user_can_push_to_ref?
  def current_user_can_push_to_ref?(ref)
    if defined?(@current_user_can_push_to_ref) && !@current_user_can_push_to_ref[ref].nil?
      @current_user_can_push_to_ref[ref]
    else
      @current_user_can_push_to_ref ||= {}
      @current_user_can_push_to_ref[ref] = current_repository.pushable_by?(current_user, ref: ref)
    end
  end

  helper_method :current_user_has_fork?
  memoize def current_user_has_fork?
    current_repository && logged_in? && current_repository.network_has_fork_for?(current_user)
  end

  helper_method :current_user_can_fork?
  memoize def current_user_can_fork?
    current_repository && logged_in? && current_user.can_fork?(current_repository)
  end

  def request_reflog_data(via)
    {
      real_ip: request.remote_ip,
      repo_name: current_repository.name_with_display_owner,
      repo_public: current_repository.public?,
      user_login: current_user.login, # rubocop:todo GitHub/DoNotAllowLogin https://github.com/github/proxima/issues/1336
      user_agent: request.user_agent,
      from: GitHub.context[:from],
      via: via,
    }
  end

  # Use in before filters to restrict to admin access
  def ensure_admin_access
    render_access_denied unless current_repository.adminable_by?(current_user)
  end

  # Use in before filters to restrict to access to actions settings
  def ensure_actions_settings_access
    if current_repository.owner.feature_enabled?(:repo_ci_cd_admin)
      render_access_denied unless current_repository.can_write_repository_actions_settings?(current_user)
    else
      render_access_denied unless current_repository.adminable_by?(current_user)
    end
  end

  def ensure_actions_environments_access
    if current_repository.owner.feature_enabled?(:repo_ci_cd_admin)
      render_404 unless current_repository.can_write_repository_actions_environments?(current_user)
    else
      render_404 unless current_repository.adminable_by?(current_user)
    end
  end

  def ensure_actions_runners_access
    if current_repository.owner.feature_enabled?(:repo_ci_cd_admin)
      render_access_denied unless current_repository.can_write_repository_actions_runners?(current_user)
    else
      render_access_denied unless current_repository.adminable_by?(current_user)
    end
  end

  def manage_security_products_permission_required
    if current_repository.owner&.organization?
      render_access_denied unless SecurityProduct::Permissions::RepoAuthz.new(current_repository, actor: current_user).can_manage_security_products?
    else
      ensure_admin_access
    end
  end

  def render_access_denied
    if logged_in? && current_user.site_admin?
      render "admin/locked_repo"
    else
      render_404
    end
  end

  # True if this repository is offline. Templates should be careful about
  # accessing git data when this is true. This flag is set by the render_offline
  # method which is called when a RepositoryOffline exception is rescued from an
  # action.
  def repository_offline?
    @repository_offline
  end
  helper_method :repository_offline?

  # This is a separate method because it's used for rescue_from. The contract for
  # rescue_from is that it gets passed the exception as the first argument if the
  # arity of the method 1. If it would use render_offline directly, it would
  # pass the exception in the state variable.
  #
  # This would cause a 404 because it would use the exception message as
  # template name and it would not find that template
  def render_repository_offline
    render_offline
  end

  def render_offline(state = "offline")
    @repository_offline = true
    GitHub.dogstats.increment("repo", tags: ["action:render_offline", "state:#{state}"])

    case state
    when "offline"
      render "repositories/states/offline"
    when "down"
      render "repositories/states/down"
    else
      render_404
    end
  end

  def render_down_for_maintenance
    render_offline("down")
  end

  def instrument_issue_creation_via_ui(issue)
    return unless [PullRequest, Issue].any? { |klass| issue.kind_of?(klass) }
    prefix = issue.class.name.underscore

    has_body_template = T.let(false, T.untyped)


    ActiveRecord::Base.connected_to(role: :reading) do
      has_body_template = issue.has_body_template?
    end

    if has_body_template
      tags = ["action:create_with_template"]
      if issue.template.present?
        tags << "template:#{issue.template.parameterized_name}"
      else
        tags << "template:legacy_issue_template"
      end
      GitHub.dogstats.increment(prefix, tags: tags)
    else
      GitHub.dogstats.increment(prefix, tags: ["action:create_without_template"])
    end
  end

  def instrument_saved_reply_use(saved_reply_id, comment_type)
    return unless saved_reply_id.present?
    if saved_reply = current_user.saved_replies.find_by_id(saved_reply_id)
      GitHub.dogstats.increment("saved_reply", tags: ["action:use", "type:#{comment_type}"])
    end
  end

  def enforce_plan_supports_insights
    return if current_repository.plan_supports?(:insights)
    redirect_to network_dependencies_path(current_repository.owner, current_repository), flash: {
      plan_upgrade: true,
    }
  end

  # Override in controller to allowlist routes for advisory workspace repositories.
  # See https://github.com/github/pe-repos/issues/90.
  def route_supports_advisory_workspaces?
    false
  end

  def ensure_advisory_workspace_allowed
    return unless current_repository
    return if route_supports_advisory_workspaces?
    if current_user&.feature_enabled?(:magic_shell_caching)
      return unless magic_shell.repo_is_advisory_workspace?
    else
      return unless current_repository.advisory_workspace?
    end
    log(ns: "github/repo_advisories",
        controller: params[:controller],
        action: params[:action],
        error: "Invalid AdvisoryWorkspace Route",
        request_id: request_id)
    GitHub.dogstats.increment("invalid_advisory_workspace_route", tags: [
      "controller:#{params[:controller]}",
      "action:#{params[:action]}",
    ])

    render_404
  end

  def set_repo_as_hovercard_subject
    set_hovercard_subject(current_repository) if current_repository
  end

  def used_by_sidebar_cache_key
    if current_repository.used_by_package_id
      "repositories:used_by_sidebar:#{current_repository.id}:#{current_repository.used_by_package_id}:v2"
    else
      "repositories:used_by_sidebar:#{current_repository.id}:v2"
    end
  end
  helper_method :used_by_sidebar_cache_key

  # Internal: Does this controller support deferred loading of commit signature badges?
  # Override in downstream controllers where appropriate.
  #
  # Returns a Boolean.
  def defer_commit_badges?
    false
  end
  helper_method :defer_commit_badges?

  # Internal: Does this controller support deferred loading of status check rollups?
  # Override in downstream controllers where appropriate.
  #
  # Returns a Boolean.
  def defer_status_check_rollups?
    false
  end
  helper_method :defer_status_check_rollups?

  def parent_repository_can_have_actions_on_private_forks?(repository = current_repository)
    repo = repository.parent_advisory&.repository
    return false unless repo

    repo.actions_enabled? &&
      repo.feature_enabled?(:maintainer_love_advisory_workspaces_can_use_actions)
  end
  helper_method :parent_repository_can_have_actions_on_private_forks?
end
