# typed: true
# frozen_string_literal: true

class MilestonesController < AbstractRepositoryController

  include Issues::RateLimitsDependency
  include IssuesReactHelper

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Notify,
    ApplicationRecord::Repositories,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Spokes,
    optional: false, only: [:index, :show]

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Spokes,
    optional: false, only: [:edit, :new]

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Spokes,
    optional: false, only: [:issues]

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Notify,
    ApplicationRecord::Permissions,
    ApplicationRecord::Repositories,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Spokes,
    optional: false, only: [:paginated_issues]

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Notify,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    optional: false, only: [:paginate_milestones]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :edit, :issues, :new, :show, :paginate_milestones, :paginated_issues], optional: true

  CLOSED_PER_PAGE = 25
  OPEN_PER_PAGE = 100
  MAX_PER_PAGE = GitHub::Prioritizable::MAXIMUM_PRIORITIZABLE_ITEM_COUNT

  MILESTONES_PER_PAGE = 50
  MAX_PAGINATION = 500

  before_action :writable_repository_required, except: [:index, :show, :issues, :paginate_milestones, :paginated_issues]
  before_action :milestone_must_exist, except: %w(create index paginate_milestones new)
  before_action :modifiers_only, except: [:index, :show, :issues, :paginate_milestones, :paginated_issues]
  before_action :set_client_uid, only: [:prioritize]
  layout "repository"

  javascript_bundle :"issues-react", only: [:show], if: -> { T.bind(self, IssuesReactHelper); issue_react_milestone_show_enabled? }

  RATE_LIMITS_FEATURES = [
    :issues_service_mutative_actions_rate_limits, # are rate limits for issues-owned controller/actions enabled
    :issues_service_mutative_actions_rate_limits_new_max, # what are the new max rate limits for issues-owned controller/actions
    :issues_rate_limit_circuit_breaker, # whether to enable the circuit breaker for spammy users creating issues via issues#create
  ]

  preload_features RATE_LIMITS_FEATURES

  rate_limit_requests \
    max: :issues_service_rate_limits_max,
    ttl: 1.hour,
    key: :default_rate_limit_key,
    at_limit: :issues_service_rate_limits_at_limit,
    if: :issues_service_rate_limits_enabled?

  rate_limit_requests \
    only: [:index],
    max: ISSUES_BOT_RATE_LIMIT_MAX,
    ttl: 1.minute,
    key: :issues_bot_rate_limit_key,
    if: :issues_bot_rate_limiting_enabled?,
    at_limit: :issues_bot_rate_limit_at_limit

  def index
    @counts = {
      open: current_repository.milestones.open_milestones.count,
      closed: current_repository.milestones.closed_milestones.count,
    }

    if params[:state] == "closed"
      @has_milestones_for_state = @counts[:closed] > 0
    else
      @has_milestones_for_state = @counts[:open] > 0
    end

    render "milestones/index"
  end

  def paginate_milestones # rubocop:todo GitHub/UseRestfulActions
    # don't accept processing if current page is less than one.
    return head :bad_request if current_page < 1

    current_milestones_pagination = current_milestones

    respond_to do |format|
      format.html do
        render partial: "milestones/paginate_milestones", locals: {
          milestones: current_milestones_pagination[:milestones],
          next_page: current_milestones_pagination[:next_page],
          is_last_page: current_milestones_pagination[:is_last_page],
        }
      end
    end
  end

  def new
    @milestone = current_repository.milestones.new
    render "milestones/new"
  end

  def create
    @milestone = current_repository.milestones.build(milestone_params)
    @milestone.created_by = current_user
    @milestone.repository = current_repository

    if @milestone.save
      redirect_to milestones_path(current_repository.owner, current_repository) + "?with_issues=no"
    else
      flash.now[:error] = @milestone.errors.full_messages.to_sentence
      render "milestones/new"
    end
  end

  def show
    return if issue_react_milestone_show_handler

    view = create_view_model(
      Milestones::ShowView,
      milestone: current_milestone,
      issues: current_milestone_issues,
      showing_closed: params[:closed] == "1"
    )
    render "milestones/show", locals: { view: view }
  end

  def issues # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html do
        render partial: "milestones/issue_list", locals: {
          view: create_view_model(Milestones::ShowView,
            milestone: current_milestone,
            issues: current_milestone_issues,
            showing_closed: params[:closed] == "1"
          )
        }
      end
    end
  end

  def paginated_issues # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html do
        render partial: "milestones/paginated_issue_list", locals: {
          view: create_view_model(Milestones::ShowView,
            milestone: current_milestone,
            issues: current_milestone_issues(per_page: OPEN_PER_PAGE)
          )
        }
      end
    end
  end

  def edit
    render "milestones/edit"
  end

  def toggle # rubocop:todo GitHub/UseRestfulActions
    if current_milestone.toggle_state!
      redirect_to milestones_path(current_repository.owner, current_repository)
    else
      render "milestones/index"
    end
  end

  def update
    return render "milestones/edit" unless current_milestone

    if current_milestone.update(milestone_params)
      redirect_to milestones_path(current_repository.owner, current_repository)
    else
      render "milestones/edit"
    end
  end

  def destroy
    current_milestone.destroy
    flash[:notice] = "Milestone deleted"

    if T.must(request).xhr?
      head 200
    else
      redirect_to milestones_path(current_repository.owner, current_repository)
    end
  end

  def prioritize # rubocop:todo GitHub/UseRestfulActions
    if params[:timestamp].to_i != current_milestone.updated_at.to_i
      GitHub.dogstats.increment "issue", tags: ["action:prioritize", "via:web", "error:outdated"]
      respond_to do |format|
        format.json { render json: { error: "outdated" } }
      end
      return
    end

    # This shouldn't happen (the UI is disabled), so at least we won't 500.
    unless current_milestone.prioritizable?
      GitHub.dogstats.increment "issue", tags: ["action:prioritize", "via:web", "error:too_many"]
      respond_to do |format|
        format.json { render json: { error: "too_many" } }
      end
      return
    end

    issue = current_milestone.issues.find(params[:item_id])

    begin
      if params[:prev_id].present?
        after = current_milestone.issues.find(params[:prev_id])
        current_milestone.prioritize_issue!(issue, after: after)
      else
        current_milestone.prioritize_issue!(issue, position: :top)
      end
    rescue GitHub::Prioritizable::Context::LockedForRebalance
      GitHub.dogstats.increment("milestones.exceptions.locked_for_rebalance", { tags: ["context:milestones_controller.prioritize"] })
      return render status: 503, plain: "Sorry! This milestone is temporarily locked for maintenance. Please try again."
    end

    GitHub.dogstats.increment "issue", tags: ["action:prioritize", "via:web", "response:success"]

    respond_to do |format|
      format.json do
        render json: {
          updated_at: current_milestone.reload.updated_at.to_i,
        }
      end
    end
  end

  protected

  def current_milestones
    offset = (current_page - 1) * MILESTONES_PER_PAGE

    scope = current_repository.milestones

    case params[:state]
    when "open"
      scope = scope.open_milestones
    when "closed"
      scope = scope.closed_milestones
    else
      scope = scope.open_milestones
    end

    scope = scope.sorted_by(params[:sort], params[:direction])

    total_count = scope.count

    milestones = scope
      .offset(offset)
      .limit(MILESTONES_PER_PAGE)
      .to_a

    {
      milestones: milestones,
      next_page: current_page + 1,
      is_last_page: (current_page - 1) * MILESTONES_PER_PAGE + milestones.size >= total_count
    }
  end

  memoize def current_milestone
    if params[:id]
      current_repository.milestones.find_by_number(params[:id])
    elsif params[:number]
      current_repository.milestones.find_by_number(params[:number])
    elsif params[:slug]
      current_repository.milestones.find_by_slug(params[:slug])
    end
  end
  helper_method :current_milestone

  def milestone_must_exist
    unless current_milestone
      render_404
    end
  end

  def current_milestone_issues(per_page: MAX_PER_PAGE)
    state = params[:closed] == "1" ? :closed : :open

    closed = params[:closed] == "1"
    per_page = closed ? CLOSED_PER_PAGE : per_page

    @current_milestone_issues ||= current_milestone.issues_to_render_for_viewer(
      current_user,
      state: state,
      page: current_page,
      per_page: per_page,
    )
  end

  def modifiers_only
    return redirect_to_login unless logged_in?
    return redirect_to "/" unless current_repository
    redirect_to "/" unless current_user_can_push?
  end

  private

  def milestone_params
    params.require(:milestone).permit %i[title description due_on state body]
  end

  def max_pagination_page
    MAX_PAGINATION
  end
end
