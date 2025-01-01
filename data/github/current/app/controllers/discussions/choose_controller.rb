# typed: true
# frozen_string_literal: true

class Discussions::ChooseController < Discussions::BaseController
  before_action :login_required_redirect_for_public_repo, only: :show
  before_action :set_org_context_crumb, only: :show, if: :is_org_level?
  before_action :require_create_permissions, only: :show

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  preload_features [
    :permission_enforcer_with_caching,
    :notifyd_label_subscriptions,
    :skip_open_graph_url_encoding,
    :stacks_toggle,
    :otel_rack_middleware,
    :two_factor_checkup,
    :notifications_async_watch_repo_button,
    :allow_internal_org_config_repo_if_public_repos_disabled, # Global health repo for EMU orgs
    :global_health_files_repository_loader_new_fetch_implementation, # Global health repo for EMU orgs
    :emu_vss_business,
    :all_repo_roles,
    :enterprise_banners_repo_level,
    :authenticated_avatars,
    :api_insights_rest,
    :copilot_conversational_ux_license_check,
    :copilot_for_partners,
    :owner_scoped_github_apps,
    :interaction_limit_kv_fallback,
    :stafftools_tenant_use_parameter,
    :proxima_repository_advisories,
    :copilot_natural_language_github_search,
    :skip_anon_jump_to_suggestions_enabled,
  ]

  def show
    current_repository = self.current_repository
    if current_repository && current_repository.organization_discussion.present? & !is_org_level?
      return redirect_to org_choose_category_discussion_path(current_repository.organization)
    end

    available_categories = current_repository&.available_discussion_categories_for_actor(current_user) ||
      DiscussionCategory.none
    render "discussions/choose/show",
      locals: {
        discussion_categories: available_categories
      }
  end

  private

  def set_org_context_crumb
    return unless header_redesign_enabled?
    return if this_organization.nil?
    set_nav_breadcrumb ContextRegion::Factory.build(this_organization, current_user: current_user)
  end

  def require_create_permissions
    unless current_user.can_create_discussion?(current_repository)
      flash[:error] = "You can't perform that action at this time."
      redirect_to agnostic_discussions_path(org_param: org_param)
    end
  end
end
