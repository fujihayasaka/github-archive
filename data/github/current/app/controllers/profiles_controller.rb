# typed: true
# frozen_string_literal: true

class ProfilesController < ApplicationController
  include ProfilesHelper
  include Profiles::ContributionGraphDependency

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Authnd,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Spokes,
    ApplicationRecord::Ballast,
    ApplicationRecord::Iam,
    ApplicationRecord::Collab,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::Memex,
    ApplicationRecord::Collab,
    ApplicationRecord::Iam,
    only: [:tab_counts]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  DEFAULT_PAGE_SIZE = 30

  rate_limit_requests \
    only: :show,
    ttl: :profiles_rate_limit_ttl,
    max: :profiles_rate_limit_max,
    key: :profiles_rate_limit_key

  # As of 2019-04-16, show is averaging around 565 rq/sec, or around 3%
  # of total requests
  set_statsd_sample_rate 0.01, only: :show

  include Orgs::Invitations::RateLimiting
  include UserContributionsHelper
  include Registry::QueryHelper

  # Once a repository has been expanded, how many issues, PRs, or PR reviews should be shown?
  CONTRIBS_PER_REPO_LIMIT = 25

  # How many repositories should be shown in issue, PR review, and PR rollups
  REPOS_PER_ROLLUP_LIMIT = 25

  around_action :record_profile_stats, only: %w( show )
  skip_before_action :cap_pagination, only: %w( show )

  before_action :require_xhr, only: :tab_counts
  before_action :ensure_user_visible, only: %i(show tab_counts)

  javascript_bundle :profile
  stylesheet_bundle :profile
  stylesheet_bundle :insights, only: %w( show )

  def this_organization # rubocop:todo GitHub/UseRestfulActions
    this_user if this_user&.organization?
  end
  helper_method :this_organization

  def tab_counts # rubocop:todo GitHub/UseRestfulActions
    results = {}

    if this_user.organization?
      # This response structure is a bit odd, but it's implemented this way to keep compatibility
      # with the JS front end code, which used to call out for a GraphQL response.
      results[:teams] = { totalCount: this_user.visible_teams_for(current_user).count } if params[:team].present?
      results[:members] = { totalCount: this_user.visible_user_ids_for(current_user, limit: nil).count } if params[:member].present?

      # This is a feature-flagged optimization based on the results of the org_tab_count_private_ari experiment.
      #
      # When a user is viewing an org profile, we can use a more efficient scope to get visible repos, and
      # use it to generate a repo count and to further scope down the list of packages to count.
      #
      # Bots cannot currently use this optimization because their version of ARI doesn't support org scoping yet,
      # but the recent batched range optimization to org scoping for users may work for bots as well, at which
      # point this could become a more general optimization.
      #
      # :org_scoped_ari is a legacy feature flag meant to improve performance for specific users.
      if params[:repo].present?
        if hide_repository_tab_count?(this_user)
          visible_owned_repositories = nil
        elsif GitHub.flipper[:org_scoped_ari].enabled?(current_user)
          visible_owned_repositories = this_user.
            visible_repositories_for_candidate(current_user).
            where(owner_id: this_user.id)
        else
          visible_owned_repositories = org_repo_ids
        end
      end

      if params[:discussion].present? && current_repository&.discussions_active?
        results[:discussions] = {
          totalCount: this_user.visible_discussions_for(current_user).count
        }
      end
    elsif logged_in?
      # This is getting counts for a user viewing a user profile - since it's possible that
      # this_user != current_user, should this be current_user.associated_repository_ids?
      visible_owned_repositories = this_user.associated_repository_ids(repository_ids: this_user.repository_ids)
    else
      visible_owned_repositories = this_user.repositories.public_scope
    end

    if params[:repo].present? && !visible_owned_repositories.nil?
      results[:repositories] = { totalCount: visible_owned_repositories.count }
    end

    # An owner's packaged repo count tends to be much smaller than the overall repository count,
    # with large orgs on the scale of hundreds (with an outlier at 1800) vs in the hundreds of
    # thousands for overall repo count. By using this to reduce the list of all org repo IDs
    # accessible to the user, the IN clause for where(repository_id: ids) should never grow too large.
    #
    # Eg for orgs: https://data.githubapp.com/sql/share/c47bfa54
    if params[:package].present?
      active_owned_packages = this_user.packages.joins(:package_versions).merge(Registry::PackageVersion.not_deleted)
      package_repo_ids = active_owned_packages.distinct.pluck(:repository_id)
      visible_package_repo_ids = if current_user
        current_user.associated_repository_ids(repository_ids: package_repo_ids)
      else
        Repository.active.public_scope.where(id: package_repo_ids).pluck(:id)
      end
      visible_packages = active_owned_packages.where(repository_id: visible_package_repo_ids).distinct
      results[:packages] = { totalCount: visible_packages.count }
    end

    if params[:project].present?
      projects_count = open_memex_projects_count(this_user)

      # Projects classic is currently being sunset.
      # If the user still has projects classic UI enabled, we should include the count of open projects
      current_org = this_user.organization? ? this_user : nil
      projects_count += this_user.visible_projects_for(current_user).open_projects.count if ProjectsClassicSunset.projects_classic_ui_enabled?(current_user, org: current_org)

      results[:projects] = { totalCount: projects_count }
    end

    respond_to do |format|
      format.json do
        render json: { data: results }
      end
    end
  end

  def show
    # We're shortcircuiting this for mannequins as it is causing 500s down the line
    return render_404 if this_user.mannequin?

    return if render_user_event

    @feed_title = "#{this_user}’s Activity"
    if this_user.organization?
      return render_404 if this_user.deleted?

      @current_organization = this_user
      @current_organization.reset_public_members! if GitHub.cache.skip
      set_hovercard_subject(this_user)
      record_org_profile_visitor_stats
    end

    respond_to do |format|
      format.html do
        if this_user.organization?
          request.env[GitHub::TaggingHelper::PROFILE_TYPE] = "organization"
          render_organization_profile
        elsif (this_user.private_profile_for?(current_user) || view_private_profile?) && !private_profile_override?
          request.env[GitHub::TaggingHelper::PROFILE_TYPE] = "private_user"
          render_private_user_profile
        else
          hydro_tracking.publish_user_profile_page_view
          request.env[GitHub::TaggingHelper::PROFILE_TYPE] = "user"
          render_user_profile
        end
      end
      format.json do
        docs_url = "#{GitHub.developer_help_url}/v3/activity/events/#list-public-events-performed-by-a-user"
        render json: gone_payload(docs_url), status: 410
      end
      format.all do
        head :not_acceptable
      end
    end
  end

  private

  def org_repo_ids
    # The current user may be allowed to see this org's private repos if those repos are private forks
    # of repos owned by an org the user is an admin of. If this org has no private forks, there's
    # no need to check for this case, and if the user is an admin of this org they'll be able to
    # see those repos without a special oopfs check via their admin access.
    include_oopfs = !(this_user.adminable_by?(current_user) || this_user.repositories.forks.private_scope.none?)


    this_user.visible_repositories_for(
      current_user,
      # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded
      associated_repository_ids: current_user&.associated_repository_ids(include_oopfs: include_oopfs),
      # rubocop:enable GitHub/DontCallAssociatedRepositoryIdsUnbounded
      limit_visible_internal_repos_to_org: true
    ).where(owner_id: this_user.id).ids
  end

  # Render a 404 if there is no user or the user is hidden from the viewer
  def ensure_user_visible
    return if this_user && !this_user.hide_from_user?(current_user)
    render_404
  end

  helper_method :this_user

  def member_content_for_user?
    this_user.create_org_profile_readme(type: "member").visible? || this_user.pinned_items(viewer: current_user, internal_view: true).any?
  end

  def get_view_as_for_member
    # Suggest public view if there is no member content (can be overridden with view_as=member query parameter)
    # https://github.com/github/special-projects/issues/866#issue-1114179376
    view_as = member_content_for_user? ? "member" : "public"

    # Override with query parameter if present
    view_as = params[:view_as] || view_as

    # Enforce "member" view for EMU org member since they cannot have public repos
    this_user.enterprise_managed_user_enabled? ? "member" : view_as
  end

  def get_view_as
    unless this_user.organization? && this_user.direct_or_team_member?(current_user)
      return "public"
    end

    get_view_as_for_member
  end

  def render_organization_profile
    view_as = get_view_as
    org_profile_readme = @current_organization.create_org_profile_readme(type: view_as)
    viewing_as_member = view_as == "member"
    item_showcase = ProfileItemShowcase.new(user: @current_organization, viewer: current_user, viewing_as_member: viewing_as_member)
    any_pinnable_items = @current_organization.async_any_pinnable_items?(
      viewer: current_user,
      types: ProfilePin.pinned_item_types.keys,
      internal_view: viewing_as_member
    ).sync
    viewer_can_change_pinned_items = @current_organization.can_pin_profile_items?(current_user)

    GlobalInstrumenter.instrument(
      "user_profile.repositories.page_view",
      profile_user: this_user,
      profile_viewer: current_user,
      is_organization: true,
      selected_sort: repository_sort,
    )
    if request.xhr? || pjax?
      if request.path == user_path(@current_organization)
        layout_data = Profiles::Organization::LayoutData.preload(
          profile_organization: @current_organization,
          viewer: current_user,
          active_tab: :overview,
          phrase: search_query,
          type_filter: params[:type],
          sort_order: params[:sort],
          language: params[:language],
          view_as: get_view_as,
        )

        repos_component = Profiles::Organization::Overview::RepositoriesComponent.new(profile_layout_data: layout_data, user_session: user_session)

        render Profiles::Organization::Overview::Repositories::ResultsComponent.new(
          profile_layout_data: layout_data,
          repositories: repos_component.repositories,
        ), layout: false
      else
        # Show the partial with two columns
        render partial: "orgs/repositories/columns", locals: {
          view: create_view_model(Orgs::Repositories::IndexPageView,
            organization: @current_organization,
            current_page: current_page,
            type_filter: params[:type],
            language: params[:language],
            sort_order: params[:sort],
            phrase: search_query,
            view_as: get_view_as,
          )
        }
      end
    elsif @current_organization.has_sdn_new_org_with_free_plan_restriction?
      render "orgs/restricted_org_notice", locals: {
        target: @current_organization,
        header_view: create_view_model(Orgs::HeaderView, organization: @current_organization),
        selected_nav_item: :overview
      }
    else
      # Show the org profile
      view = create_view_model(
        Orgs::Repositories::IndexPageView,
        organization: @current_organization,
        current_page: current_page,
        type_filter: params[:type],
        sort_order: params[:sort],
        phrase: search_query,
        rate_limited: org_invite_rate_limited?,
        language: params[:language],
        view_as: get_view_as,
        org_profile_readme: org_profile_readme,
        item_showcase: item_showcase,
        any_pinnable_items: any_pinnable_items,
        viewer_can_change_pinned_items: viewer_can_change_pinned_items,
      )
      render "orgs/index", locals: {
        view: view,
        layout_data: Profiles::Organization::LayoutData.preload(
          profile_organization: @current_organization,
          viewer: current_user,
          active_tab: :overview,
          phrase: search_query,
          sort_order: params[:sort],
          type_filter: params[:type],
          language: params[:language],
          view_as: get_view_as,
          org_profile_readme: org_profile_readme,
          item_showcase: item_showcase,
          any_pinnable_items: any_pinnable_items,
          viewer_can_change_pinned_items: viewer_can_change_pinned_items,
        )
      }
    end
  end

  memoize def search_query
    raw_query = params[:q]
    raw_query if raw_query.is_a?(String)
  end

  def render_user_profile
    if request.xhr? || pjax?
      if should_render_year_list?
        render_year_list
      else
        render_contribution_activity
      end
    else
      if this_user
        render "users/show", locals: {
          displayable_profile_highlights: this_user.displayable_profile_highlights,
          collector: async_contributions_enabled? ? nil : timeline_collector,
          layout_data: Profiles::User::LayoutData.preload(
            profile_user: this_user,
            viewer: current_user,
            active_tab: :overview,
          ),
        }
      else
        render_404
      end
    end
  end

  def render_private_user_profile
    render "users/private/show", locals: {
      viewer: current_user,
      layout_data: Profiles::User::Private::LayoutData.preload(
        profile_user: this_user,
        viewer: current_user,
        active_tab: :overview,
        previewing: preview_private_profile?
      ),
    }
  end

  def view_private_profile?
    this_user.private_profile? &&
      ((this_user == current_user && params[:preview]) ||
      current_user != this_user)
  end

  def preview_private_profile?
    this_user == current_user && params[:preview]
  end

  def render_user_event
    if request.format && request.format.atom?
      # TODO: store latest event id/timestamp somewhere so that freshness
      #       can be checked without loading the events.
      event = current_events.first
      fresh_when strong_etag: event, template: false
      performed?
    else
      false
    end
  end

  def open_memex_projects_count(owner)
    return 0 unless owner.organization?
    return 0 unless GitHub.projects_new_enabled?

    owner.accessible_memexes_scope(owner.memex_projects.open_projects, current_user).count
  end

  memoize def events_timeline_key
    "actor:#{this_user.id}:public"
  end

  def hydro_tracking
    HydroTracking.new(
      profile_user: this_user,
      profile_viewer: current_user,
      scoped_organization: scoped_organization,
      tab_param: params[:tab],
      profile_readme_rendered: show_profile_readme?,
    )
  end

  def invite_rate_limited_organization
    if this_user.organization?
      this_user
    end
  end

  def target_for_conditional_access
    # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    return :no_target_for_conditional_access unless this_user.present?
    this_user
  end

  def record_org_profile_visitor_stats
    role = if logged_in?
      if @current_organization.direct_or_team_member?(current_user)
        "member"
      else
        "non_member"
      end
    else
      "anonymous"
    end
    GitHub.dogstats.increment("organization", tags: ["action:profile_view", "role:#{role}"])
  end

  def render_contribution_activity
    headers["Cache-Control"] = "no-cache, no-store"

    # Both feature-flagged sections might want this info
    base_date = timeline_collector.time_range.first.to_date
    age = Time.current.year - base_date.year

    # If a user has specified a date range that isn't in the current year,
    # log the year/age to inform data retention needs.
    #
    # Feature-flagged in case logging is causing problems.
    if GitHub.flipper[:log_contribution_graph_age].enabled?
      GitHub.logger.info(
        "code.namespace" => "ProfilesController",
        "code.function" => "render_contribution_activity",
        "gh.contributions.year" => base_date.year,
        "gh.contributions.age" => age,
        "gh.request_id" => request_id,
      ) if age != 0
    end

    render partial: "users/tabs/contribution_activity", locals: {
      include_header: params[:include_header] != "no",
      collector: timeline_collector,
      org: scoped_organization
    }
  end

  def render_year_list
    from, to = month_date_params
    time_range = from..to
    collector = Contribution::Collector.new(
      user: this_user,
      viewer: current_user,
      time_range: time_range,
      organization_id: scoped_organization&.id,
      excluded_organization_ids: cap_filter.unauthorized_resource_ids(current_user&.organizations),
      lightweight: true,
    )
    render partial: "users/year_list", locals: {
      collector: collector, org: scoped_organization
    }
  end

  def should_render_year_list?
    params[:year_list] == "1"
  end

  sig { returns(T.nilable(String)) }
  def repository_sort
    sort_param = params[:sort]
    return unless sort_param.present?
    sort = sort_param.to_s.upcase

    Platform::Enums::RepositoryOrderField.values[sort]&.graphql_name
  end

  def record_profile_stats
    return yield unless logged_in? && this_user && !this_user.organization?

    before = Time.now
    yield
    duration = Time.now - before

    tags = ShowProfileStats.tags(
      activity_overview_rendered: activity_overview_enabled?,
      hide_spider_graph: hide_spider_graph?,
      subject_user: this_user,
      viewer: current_user,
    )

    GitHub.dogstats.distribution("user.profile.request", duration * 1000, tags: tags)
  end

  def hide_spider_graph?
    user_or_global_feature_enabled?(:hide_spider_graph)
  end

  def hide_repository_tab_count?(organization)
    organization.exceeds_owned_repo_limit?
  end
end
