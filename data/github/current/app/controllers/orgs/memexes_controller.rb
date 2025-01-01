# typed: true
# frozen_string_literal: true

class Orgs::MemexesController < Orgs::Controller
  include GitHub::Memoizer
  include MemexesHelper
  include ProjectsHelper
  include Memexes::ProjectListDependency
  include Memexes::GrantRoleOnCreateDependency
  include Memexes::ClientPathsDependency
  include Memexes::SharedMemexesControllerActions
  include ApplicationController::VerifiedFetchDependency
  include TagAttributeHelper


  MEMEX_INDEX_LIMIT = 30

  # cluster dependencies analysis will be enabled for this non-get requests
  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Orgs::MemexesController#remove_visited",
    "Orgs::MemexesController#update",
    "Orgs::MemexesController#create",
    "Orgs::MemexesController#delete",
    "Orgs::MemexesController#stats",
    "Orgs::MemexesController#copy",
    "Orgs::MemexesController#dismiss_legacy_org_banner",
    "Orgs::MemexesController#dismiss_notice",
    "Orgs::MemexesController#feedback",
  ]

  # global critical dependencies, needed for all actions
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Memex,
    ApplicationRecord::Collab

  # Project columns backed by issue fields need to query the issues and pull requests cluster to denormalize
  # the issue field values into the project columns.
  depends_on_clusters ApplicationRecord::IssuesPullRequests, only: [:create]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show, :index, :copy, :redirect_to_projects_url, :refresh],
    optional: true

  preload_features [
    :tasklist_block,
    :otel_rack_middleware,
    :two_factor_checkup,
    :enterprise_banners_repo_level,
    :emu_vss_business,
    :issues_react_global_add,
    :html_pipeline_bad_emoji,
    :api_insights_rest,
    :copilot_conversational_ux_license_check,
    :copilot_for_partners,
    :owner_scoped_github_apps,
    :stafftools_tenant_use_parameter,
    :memex_without_limits_limited_public_beta_banner_safe_rollout,
    :copilot_metered_enterprise,
    :copilot_natural_language_github_search,
    :copilot_cb_rollout,
    :copilot_ce_rollout,
    :copilot_cs_rollout,
    :copilot_limited_rollout,
    :copilot_pro_plus_rollout,
    :copilot_pro_rollout,
    :log_notifications_unauthorized_accounts,
    :reserved_domain,
    :remove_shelf_limited_paths,
    :saml_scope_private_resources_to_business,
    :issues_react_disabled,
    :enterprise_teams_org_assignment,
    :run_authzd_cap_filter_experiment_web,
    :evaluate_ip_allowlist_satisfied_debug_logging,
    :saml_filter_logging,
    :saml_satisfied_debug_logging,
    :disable_notifications_automatic_watching_repositories,
    :disable_notifications_automatic_watching_teams,
    :limit_execution_time_notification_entries,
    :notifications_remove_force_index,
    :limit_execution_time_indicator,
    :repos_domain_associations,
    :copilot_api_override_url_fallback,
    :memex_updated_team_planning_template,
  ]

  before_action :login_required, except: [:index, :show, :search, :refresh, :stats, :filter_suggestions, :feedback]
  before_action :require_memex_enabled
  before_action :require_organization_projects_enabled
  before_action :organization_read_or_outside_collaborator_required, except: [:index, :show, :refresh, :update, :delete, :search, :stats, :copy, :filter_suggestions, :feedback]
  before_action :redirect_for_view_type_query, only: [:show]
  before_action :user_has_read_access, only: [:show, :refresh, :stats, :filter_suggestions, :feedback]
  before_action :user_has_write_access, only: [:update]
  before_action :require_this_repository, only: [:search_issues_and_pulls, :count_issues_and_pulls]
  before_action :require_verified_email, except: [:index, :show, :refresh, :search_repositories, :search_issues_and_pulls, :suggested_repositories, :search, :stats, :count_issues_and_pulls, :filter_suggestions, :feedback]

  before_action :set_client_uid
  before_action :set_cache_control_no_store
  before_action :set_pwl_span_attribute, only: [:show]

  allow_verified_fetch only: [:update, :delete, :stats, :dismiss_notice, :feedback]

  javascript_bundle :"memex-index", only: [:index]

  layout "memex"

  depends_on_clusters ApplicationRecord::Repositories,
    ApplicationRecord::IssuesPullRequests, only: [:index]
  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Iam,
    ApplicationRecord::Spokes,
    ApplicationRecord::Notify, only: [:index], optional: true

  def index
    # For pagination we just want to render the items and return these to the view
    return render Memex::ProjectList::ItemsContainerComponent.new(
      **list_projects(xhr: true).merge({
        is_recent_selected: !params[:query]&.present? && has_recently_visited_projects
      })
    ), layout: false, locals: { page_title: "Projects" } if request&.xhr?

    # the recent page is active, and we only need the subset of memexes that are recent
    if !params[:query]&.present? && has_recently_visited_projects
      closed_count = recently_visited_projects.count(&:closed?)
      return render "memexes/index",
        layout: "org_projects",
        locals: {
          project_owner: this_organization,
          memexes: recently_visited_projects,
          has_next_page: false,
          cursor: nil,
          sort_query_cursor: nil,
          parsed_query: Search::Queries::MemexProjectQuery.new(params[:query]),
          open_memex_count: recently_visited_projects.count - closed_count,
          closed_memex_count: closed_count,
          has_any_memex_projects: true,
          display_legacy_org_warning: display_legacy_org_warning?,
          viewer_is_a_member: this_organization.member?(current_user),
          is_recent_selected: true,
          has_recent_projects: true,
          show_templates_index: true,
          write_accessible_project_ids: MemexProject.async_filter_accessible_memexes(current_user, recently_visited_projects, "write").sync.pluck(:id)
        }
    end

    list_projects_locals = list_projects("index")

    return redirect_to org_projects_path(
      this_organization,
      params: {
        type: params[:type],
        query: Search::Queries::MemexProjectQuery::DEFAULT_QUERY
      }
    ), status: 307 if list_projects_locals.nil?

    render "memexes/index",
      layout: "org_projects",
      locals: { **list_projects_locals.merge({
        has_any_memex_projects: this_organization.memex_projects.any?,
        display_legacy_org_warning: display_legacy_org_warning?,
        viewer_is_a_member: this_organization.member?(current_user),
        is_recent_selected: false,
        has_recent_projects: has_recently_visited_projects,
      }) }
  end

  depends_on_clusters ApplicationRecord::Collab, only: [:search]

  def search # rubocop:todo GitHub/UseRestfulActions
    GlobalInstrumenter.instrument("memex_event",
      {
        actor: current_user,
        memex_project: nil,
        memex_project_column: nil,
        memex_project_item: nil,
        name: "index_search",
        ui: "index",
        context: params[:query],
        memex_project_view: nil,
      }
    )

    redirect_to org_projects_path(this_organization, query: params[:query])
  end

  depends_on_clusters ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories, only: [:redirect_to_projects_url]
  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries, only: [:redirect_to_projects_url], optional: true

  # This action is solely to handle redirecting from /memexes/:number urls to /projects/:number
  def redirect_to_projects_url # rubocop:todo GitHub/UseRestfulActions
    # If we have a memex at this URL just redirect to the equivalent /projects/ url
    if this_memex.present?
      return redirect_to show_org_memex_path(params[:org], this_memex.number, params: request&.query_parameters)
    end

    # If we had a memex previously numbered with this number,
    # redirect to the /projects/ url for its new number
    kv_key = MemexProject.renumbered_memex_kv_key(this_organization.id, underscored_params[:memex_number])
    new_number = Memex::KV.store.get(kv_key).value { nil }

    if new_number.present?
      return redirect_to show_org_memex_path(params[:org], new_number, params: request&.query_parameters)
    end

    render_404
  end

  # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
  sig { override.returns(T::Hash[Symbol, { url: String }]) }
  def client_paths # rubocop:todo GitHub/UseRestfulActions
    return @client_paths if defined?(@client_paths)

    @client_paths ||= {
      refresh_memex: { url: refresh_org_memex_path(this_memex.owner.display_login, this_memex.number) },
      update_memex: { url: update_org_memex_path(this_memex.owner.display_login, this_memex.number) },
      delete_memex: { url: delete_org_memex_path(this_memex.owner.display_login, this_memex.number) },
      suggest_memex_collaborators: { url: memex_suggested_collaborators_path(this_memex.id) },
      suggest_memex_issue_fields: { url: memex_suggested_issue_fields_path(this_memex.id) },
      add_memex_collaborators: { url: memex_update_collaborators_path(this_memex.id) },
      remove_memex_collaborators: { url: memex_remove_collaborators_path(this_memex.id) },
      update_memex_organization_access: { url: memex_update_organization_access_path(this_memex.id) },
      get_memex_organization_access: { url: memex_get_organization_access_path(this_memex.id) },
      get_memex_collaborators: { url: memex_collaborators_path(this_memex.id) },
      create_memex_item: { url: create_memex_item_path(this_memex.id) },
      create_memex_items_bulk: { url: create_memex_items_bulk_path(this_memex.id) },
      create_memex_items_repository_bulk: { url: create_memex_items_repository_bulk_path(this_memex.id) },
      get_memex_item: { url: get_memex_item_path(this_memex.id) },
      update_memex_item: { url: update_memex_item_path(this_memex.id) },
      update_memex_items_bulk: { url: update_memex_items_bulk_path(this_memex.id) },
      delete_memex_item: { url: destroy_memex_items_path(this_memex.id) },
      archive_memex_item: { url: archive_memex_items_path(this_memex.id) },
      get_memex_paginated_items: { url: memex_items_path(this_memex.id) },
      unarchive_memex_item: { url: unarchive_memex_items_path(this_memex.id) },
      convert_memex_item_to_issue: { url: convert_to_issue_memex_items_path(this_memex.id) },
      memex_get_sidepanel_item: { url: memex_get_sidepanel_item_path(this_memex.id) },
      memex_comment_on_sidepanel_item: { url: memex_comment_on_sidepanel_item_path(this_memex.id) },
      memex_update_sidepanel_item_state: { url: memex_update_sidepanel_item_state_path(this_memex.id) },
      memex_update_sidepanel_item: { url: memex_update_sidepanel_item_path(this_memex.id) },
      memex_edit_sidepanel_comment: { url: memex_edit_sidepanel_comment_path(this_memex.id) },
      memex_update_sidepanel_item_reaction: { url: memex_update_sidepanel_item_reaction_path(this_memex.id) },
      memex_sidepanel_item_suggestions: { url: memex_sidepanel_item_suggestions_path(this_memex.id) },
      suggest_memex_item_assignees: { url: memex_item_suggested_assignees_path(this_memex.id) },
      suggest_memex_item_labels: { url: memex_item_suggested_labels_path(this_memex.id) },
      suggest_memex_item_milestones: { url: memex_item_suggested_milestones_path(this_memex.id) },
      suggest_memex_item_issue_types: { url: memex_item_suggested_issue_types_path(this_memex.id) },
      preview_markdown: { url: preview_path },
      saved_replies: { url: saved_replies_path },
      get_memex_columns: { url: memex_columns_path(this_memex.id) },
      create_memex_column: { url: create_memex_column_path(this_memex.id) },
      update_memex_column: { url: update_memex_column_path(this_memex.id) },
      import_memex_issue_fields: { url: import_memex_project_column_issue_fields_path(this_memex.id) },
      delete_memex_column: { url: destroy_memex_column_path(this_memex.id) },
      create_memex_column_option: { url: create_memex_project_column_option_path(this_memex.id) },
      update_memex_column_option: { url: update_memex_project_column_option_path(this_memex.id) },
      delete_memex_column_option: { url: destroy_memex_project_column_option_path(this_memex.id) },
      create_memex_workflow: { url: create_memex_project_workflow_path(this_memex.id) },
      update_memex_workflow: { url: update_memex_project_workflow_path(this_memex.id) },
      post_memex_stats: { url: org_memex_stats_path(this_organization.display_login, this_memex.number) },
      create_memex_view: { url: create_memex_view_path(this_memex.id) },
      update_memex_view: { url: update_memex_view_path(this_memex.id) },
      delete_memex_view: { url: destroy_memex_view_path(this_memex.id) },
      create_memex_chart: { url: create_memex_chart_path(this_memex.id) },
      show_memex_chart: { url: memex_chart_path(this_memex.id) },
      update_memex_chart: { url: update_memex_chart_path(this_memex.id) },
      delete_memex_chart: { url: destroy_memex_chart_path(this_memex.id) },
      create_memex_template: { url: create_memex_template_path(this_memex.id) },
      memex_migration: { url: memex_project_migration_path(this_memex.id) },
      memex_retry_migration: { url: memex_retry_migration_path(this_memex.id) },
      memex_cancel_migration: { url: memex_cancel_migration_path(this_memex.id) },
      memex_acknowledge_completion_migration: { url: memex_acknowledge_completion_migration_path(this_memex.id) },
      memex_items_tracked_by_parent: { url: memex_items_tracked_by_parent_path(this_memex.id) },
      memex_reindex_items: { url: reindex_memex_items_path(this_memex.id) },
      copy_memex_project_partial: { url: copy_memex_project_partial_path(this_memex.id) },
      memex_custom_templates: { url: memex_org_templates_path(this_memex.owner.display_login) },
      memex_statuses: { url: memex_statuses_path(this_memex.id) },
      create_memex_status: { url: create_memex_status_path(this_memex.id) },
      post_memex_feedback: { url: org_memex_feedback_path(this_organization.display_login, this_memex.number) },

      # We use the index path here as we don't know the id of the status to be deleted yet
      destroy_memex_status: { url: memex_statuses_path(this_memex.id), method: :delete },
      update_memex_status: { url: update_memex_status_path(this_memex.id) },

      create_notification_subscription: { url: subscribe_memex_notification_subscription_path(this_memex.id) },
      destroy_notification_subscription: { url: unsubscribe_memex_notification_subscription_path(this_memex.id) },

      memex_dismiss_notice: { url: org_memex_dismiss_notice_path(this_organization.display_login, this_memex.number) },
      memex_filter_suggestions: { url: org_memex_filter_suggestions_path(this_organization.display_login, this_memex.number) },
    }
  end
  # rubocop:enable GitHub/ControllersShouldUseMemoizeForMemoization

  def dismiss_legacy_org_banner # rubocop:todo GitHub/UseRestfulActions
    current_user
      &.dismiss_organization_notice(
        "projects_beta_legacy_warning",
        this_organization
      )

    if request&.xhr?
      head :no_content
    else
      redirect_to :back
    end
  end


  depends_on_clusters ApplicationRecord::Collab,  ApplicationRecord::Repositories, only: [:remove_visited]
  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries, only: [:remove_visited]

  depends_on_clusters ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::IssuesPullRequests, only: [:templates]
  depends_on_clusters ApplicationRecord::Iam,
    ApplicationRecord::Ballast,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Spokes,
    ApplicationRecord::Notify, only: [:templates], optional: true

  def templates # rubocop:todo GitHub/UseRestfulActions
    templates = T.cast(this_organization, Organization).memex_templates.where(active: true)

    GitHub::PrefillAssociations.prefill_associations(templates, { memex_project: [:memex_project_views, :memex_project_columns, :workflows, :charts] })
    template_projects = T.let(templates.filter_map(&:memex_project), T::Array[MemexProject])

    serialized_templates = serialize_templates(template_projects)

    recommended_project_links = T.cast(this_organization, Organization).memex_project_links

    # Prefill the `memex_project` association to prevent N+1 queries
    GitHub::PrefillAssociations.prefill_associations(recommended_project_links, { memex_project: [:memex_project_views, :memex_project_columns, :workflows, :charts] })
    recommended_templates = T.let(recommended_project_links.filter_map(&:memex_project), T::Array[MemexProject])

    serialized_recommended_templates = serialize_templates(recommended_templates)
    render(json: { templates: serialized_templates, recommendedTemplates: serialized_recommended_templates })
  end

  private

  def source
    this_organization
  end

  def load_more_path
    org_projects_path(this_organization.display_login)
  end

  def this_repository # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @this_repository if defined?(@this_repository)
    @this_repository = super
  end

  def view_redirect_params
    params.permit(
      :layout,
      :memex_number,
      :org,
      :viewType,
      groupedBy: {},
      sortedBy: {},
      verticalGroupedBy: {}
    )
  end

  def redirect_for_view_type_query
    # viewType was the original parameter we used for toggling between board
    # and table views. Now that it has been replaced with the value of
    # view_type_key, redirect users coming in with the old param.
    return unless view_type_value = params[:viewType]
    view_type_key = :layout
    rewritten_params = view_redirect_params.except(:viewType).merge(view_type_key => view_type_value)
    redirect_to safe_url_for(**rewritten_params)
  end

  def clean_observation(item)
    return unless item
    item.deep_dup.with_indifferent_access
  end

  def memex_owner
    this_organization
  end

  sig { override.returns(String) }
  def client_search_repositories_path
    org_memex_search_repositories_path(memex_owner.display_login)
  end

  sig { override.returns(String) }
  def client_search_issues_and_pulls_path
    org_memex_search_issues_and_pulls_path(memex_owner.display_login)
  end

  sig { override.returns(String) }
  def client_count_issues_and_pulls_path
    org_memex_count_issues_and_pulls_path(memex_owner.display_login)
  end

  sig { override.returns(String) }
  def client_suggested_repositories_path
    org_memex_suggested_repositories_path(memex_owner.display_login)
  end

  sig { override.params(memex: MemexProject).returns(T::Boolean) }
  def grant_role_on_create(memex)
    begin
      memex.grant_role(current_user, :admin)
      true
    rescue Permissions::Granters::RoleGranter::GrantFailure
      memex.destroy!
      render(json: { errors: ["Error occured when creating project"] }, status: :unprocessable_entity)
      false
    end
  end

  def search_repositories_scope
    "org:#{this_organization.login}" # rubocop:todo GitHub/DoNotAllowLogin https://github.com/github/proxima/issues/1194
  end

  def repo_ids_with_milestone(milestone_title)
    memex_owner.repo_ids_with_milestone(milestone_title)
  end

  def legacy_org_admin? # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @legacy_org_admin if defined?(@legacy_org_admin)

    @legacy_org_admin = this_organization.plan.legacy? &&
      Organization::Role.new(this_organization, current_user).admin?

    if @legacy_org_admin
      GitHub.logger.info(
        "legacy_org_project_warning displayed to admin",
        "gh.org.login": this_organization.display_login,
        "gh.user.id": current_user&.id,
      )
    end

    @legacy_org_admin
  end

  def require_organization_projects_enabled
    render_404 unless this_organization&.organization_projects_enabled?
  end

  def display_legacy_org_warning?
    return false unless legacy_org_admin?
    return false if legacy_org_warning_dismissed?

    true
  end

  def legacy_org_warning_dismissed?
    current_user&.dismissed_organization_notice?(
      "projects_beta_legacy_warning",
      this_organization
    )
  end

  memoize def recently_visited_projects
    return unless logged_in?

    # Perform the query and convert the relation to an array
    this_organization.recently_visited_projects(viewer: current_user, cap_filter: cap_filter).to_a
  end

  memoize def has_recently_visited_projects
    return false if recently_visited_projects.nil?
    recently_visited_projects.size > 0
  end

  sig { params(template_projects: T::Array[MemexProject]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def serialize_templates(template_projects)
    serialized_templates = []
    template_projects.each do |project|
      next if project.closed?
      next unless project.viewer_can_read?(current_user)

      fields = remove_excluded_fields(project.memex_project_columns)

      serialized_project = {
        projectTitle: project.title,
        projectNumber: project.number,
        projectViews:  project.memex_project_views.map { |view| { name: view.name, viewType: view.layout } },
        projectFields: fields.map { |field| { name: field.name, dataType: field.data_type.camelize(:lower), customField: field.user_defined } },
        projectWorkflows: T.let([], T::Array[{ name: String, triggerType: T.nilable(String) }]),
        projectCharts: T.let([], T::Array[{ name: T.nilable(String), chartType: T.nilable(String) }]),
      }

      # Auto-add workflows are not to be copied as part of a template, per our initial specification:
      # https://github.com/github/memex/issues/15830
      copyable_workflows = project.workflows.reject { |workflow| workflow.is_auto_add_workflow? }
      serialized_project[:projectWorkflows] = copyable_workflows.map { |workflow| { name: workflow.name, triggerType: workflow.trigger_type } }

      serialized_project[:projectCharts] = project.charts.map { |chart| { name: chart.name, chartType: chart.configuration["type"] } }
      serialized_project[:projectId] = project.id
      serialized_project[:projectUpdatedAt] = project.updated_at
      serialized_project[:projectDescription] = project.description
      serialized_project[:projectShortDescription] = project.short_description

      serialized_templates << serialized_project
    end
    serialized_templates
  end
end
