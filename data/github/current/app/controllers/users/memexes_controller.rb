# typed: true
# frozen_string_literal: true

class Users::MemexesController < Users::Controller
  include Memexes::GrantRoleOnCreateDependency
  include Memexes::ClientPathsDependency
  include Memexes::SharedMemexesControllerActions
  include MemexesHelper
  include ApplicationController::VerifiedFetchDependency


  # cluster dependencies analysis will be enabled for this non-get requests
  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Users::MemexesController#remove_visited",
    "Users::MemexesController#update",
    "Users::MemexesController#create",
    "Users::MemexesController#delete",
    "Users::MemexesController#stats",
    "Users::MemexesController#copy",
    "Users::MemexesController#dismiss_notice",
    "Users::MemexesController#feedback",
  ]

  # global critical dependencies, needed for all actions
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Memex,
    ApplicationRecord::Collab

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Repositories,
    ApplicationRecord::NotificationsEntries, only: [:remove_visited]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show, :copy, :refresh],
    optional: true

  preload_features [
    :tasklist_block,
    :otel_rack_middleware,
    :two_factor_checkup,
    :html_pipeline_bad_emoji,
    :issues_react_global_add,
    :api_insights_rest,
    :copilot_conversational_ux_license_check,
    :ip_allowlist_user_level_enforcement,
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
    :run_authzd_cap_filter_experiment_web,
    :saml_satisfied_debug_logging,
    :disable_notifications_automatic_watching_repositories,
    :disable_notifications_automatic_watching_teams,
    :enterprise_teams_temp_abilities_query_with_indirect,
    :limit_execution_time_notification_entries,
    :notifications_remove_force_index,
    :limit_execution_time_indicator,
    :repos_domain_associations,
    :copilot_api_override_url_fallback,
    :memex_updated_team_planning_template,
  ]

  before_action :login_required, except: [:show, :refresh, :stats, :filter_suggestions, :feedback]
  before_action :require_memex_enabled
  before_action :require_user_projects_enabled
  before_action :require_memex_owner
  before_action :require_viewer_is_owner, only: [:create]
  before_action :user_has_read_access, only: [:show, :refresh, :stats, :filter_suggestions, :feedback]
  before_action :user_has_read_access_if_this_memex_present, only: [:search_repositories, :search_issues_and_pulls, :suggested_repositories, :count_issues_and_pulls]
  before_action :user_has_write_access, only: [:update]
  before_action :require_this_repository, only: [:search_issues_and_pulls, :count_issues_and_pulls]
  before_action :require_verified_email, except: [:show, :refresh, :search_repositories, :search_issues_and_pulls, :suggested_repositories, :stats, :count_issues_and_pulls, :filter_suggestions, :feedback]

  before_action :set_client_uid
  before_action :set_cache_control_no_store
  before_action :set_pwl_span_attribute, only: [:show]

  allow_verified_fetch only: [:update, :delete, :stats, :dismiss_notice, :feedback]

  layout "memex"

  # Safe because memex_owner is required (memex_owner is always this_user if present, or current_user if creating a memex)
  private def target_for_conditional_access
    return :no_target_for_conditional_access unless this_user # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    this_user
  end

  def memex_owner # rubocop:todo GitHub/UseRestfulActions
    return this_user if this_user.present?
    current_user if params[:action] == "new"
  end

  sig { override.returns(String) }
  def client_search_repositories_path # rubocop:todo GitHub/UseRestfulActions
    user_memex_search_repositories_path(memex_owner.display_login)
  end

  sig { override.returns(String) }
  def client_search_issues_and_pulls_path # rubocop:todo GitHub/UseRestfulActions
    user_memex_search_issues_and_pulls_path(memex_owner.display_login)
  end

  sig { override.returns(String) }
  def client_count_issues_and_pulls_path # rubocop:todo GitHub/UseRestfulActions
    user_memex_count_issues_and_pulls_path(memex_owner.display_login)
  end

  sig { override.returns(String) }
  def client_suggested_repositories_path # rubocop:todo GitHub/UseRestfulActions
    user_memex_suggested_repositories_path(memex_owner.display_login)
  end

  def require_viewer_is_owner # rubocop:todo GitHub/UseRestfulActions
    render_404 unless memex_owner == current_user
  end

  def require_memex_owner # rubocop:todo GitHub/UseRestfulActions
    render_404 unless memex_owner.present?
  end

  sig { override.params(memex: MemexProject).returns(T::Boolean) }
  def grant_role_on_create(memex) # rubocop:todo GitHub/UseRestfulActions
    true
  end

  # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
  sig { override.returns(T::Hash[Symbol, { url: String }]) }
  def client_paths # rubocop:todo GitHub/UseRestfulActions
    return @client_paths if defined?(@client_paths)

    @client_paths ||= {
      refresh_memex: { url: refresh_user_memex_path(this_memex.owner.display_login, this_memex.number) },
      update_memex: { url: update_user_memex_path(this_memex.owner.display_login, this_memex.number) },
      delete_memex: { url: delete_user_memex_path(this_memex.owner.display_login, this_memex.number) },
      suggest_memex_collaborators: { url: memex_suggested_collaborators_path(this_memex.id) },
      suggest_memex_issue_fields: { url: memex_suggested_issue_fields_path(this_memex.id) },
      add_memex_collaborators: { url: memex_update_collaborators_path(this_memex.id) },
      remove_memex_collaborators: { url: memex_remove_collaborators_path(this_memex.id) },
      update_memex_organization_access: nil, # not supported for user-owned memex
      get_memex_organization_access: nil, # not supported for user-owned memex
      get_memex_collaborators: { url: memex_collaborators_path(this_memex.id) },
      create_memex_item:  { url: create_memex_item_path(this_memex.id) },
      create_memex_items_bulk: { url: create_memex_items_bulk_path(this_memex.id) },
      create_memex_items_repository_bulk: { url: create_memex_items_repository_bulk_path(this_memex.id) },
      get_memex_item: { url: get_memex_item_path(this_memex.id) },
      update_memex_item: { url: update_memex_item_path(this_memex.id) },
      update_memex_items_bulk: { url: update_memex_items_bulk_path(this_memex.id) },
      delete_memex_item: { url: destroy_memex_items_path(this_memex.id) },
      archive_memex_item: { url: archive_memex_items_path(this_memex.id) },
      unarchive_memex_item: { url: unarchive_memex_items_path(this_memex.id) },
      get_memex_paginated_items: { url: memex_items_path(this_memex.id) },
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
      delete_memex_column: { url: destroy_memex_column_path(this_memex.id) },
      create_memex_column_option: { url: create_memex_project_column_option_path(this_memex.id) },
      update_memex_column_option: { url: update_memex_project_column_option_path(this_memex.id) },
      delete_memex_column_option: { url: destroy_memex_project_column_option_path(this_memex.id) },
      create_memex_workflow: { url: create_memex_project_workflow_path(this_memex.id) },
      update_memex_workflow: { url: update_memex_project_workflow_path(this_memex.id) },
      post_memex_stats: { url: user_memex_stats_path(memex_owner, this_memex.number) },
      create_memex_view: { url: create_memex_view_path(this_memex.id) },
      update_memex_view: { url: update_memex_view_path(this_memex.id) },
      delete_memex_view: { url: destroy_memex_view_path(this_memex.id) },
      create_memex_chart: { url: create_memex_chart_path(this_memex.id) },
      import_memex_issue_fields: { url: import_memex_project_column_issue_fields_path(this_memex.id) },
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
      memex_custom_templates: nil, # not supported for user-owned memex
      memex_statuses: { url: memex_statuses_path(this_memex.id) },
      create_memex_status: { url: create_memex_status_path(this_memex.id) },
      post_memex_feedback: { url: user_memex_feedback_path(memex_owner, this_memex.number) },

      # We use the index path here as we don't know the id of the status to be deleted yet
      destroy_memex_status: { url: memex_statuses_path(this_memex.id), method: :delete },
      update_memex_status: { url: update_memex_status_path(this_memex.id) },

      create_notification_subscription: { url: subscribe_memex_notification_subscription_path(this_memex.id) },
      destroy_notification_subscription: { url: unsubscribe_memex_notification_subscription_path(this_memex.id) },

      memex_dismiss_notice: { url: user_memex_dismiss_notice_path(memex_owner.display_login, this_memex.number) },
      memex_filter_suggestions: { url: user_memex_filter_suggestions_path(memex_owner.display_login, this_memex.number) },
    }
  end
  # rubocop:enable GitHub/ControllersShouldUseMemoizeForMemoization

  def search_repositories_scope # rubocop:todo GitHub/UseRestfulActions
    "user:#{memex_owner.display_login}"
  end

  def repo_ids_with_milestone(milestone_title) # rubocop:todo GitHub/UseRestfulActions
    memex_owner.repo_ids_with_milestone(milestone_title)
  end
end
