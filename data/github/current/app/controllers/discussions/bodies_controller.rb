# typed: true
# frozen_string_literal: true

class Discussions::BodiesController < Discussions::BaseController
  before_action :require_discussion
  preload_features [
    :discussion_post_as_admin,
    :api_insights_rest,
    :owner_scoped_github_apps,
    :interaction_limit_kv_fallback,
    :stafftools_tenant_use_parameter,
    :reserved_domain,
    :remove_shelf_limited_paths,
    :lifecycle_label_name_updates,
    :enterprise_teams_crud,
    :enterprise_teams_org_assignment,
    :enterprise_teams_org_roles,
    :erp_preview_enterprise_teams_org_roles,
    :erp_staffship_enterprise_teams_org_roles,
    :use_billing_locked_rather_than_disabled,
    :saml_satisfied_debug_logging,
    :check_enterprise_teams_org_roles_enabled_repos,
    :enterprise_teams_org_authorization,
    :enterprise_teams_org_assignment,
    :erp_preview_enterprise_teams_org_assignment,
    :erp_staffship_enterprise_teams_org_assignment,
    :all_repo_role_allowed_action_for_actor_experiment,
    :enterprise_teams_esm,
    :erp_preview_enterprise_teams_esm,
    :erp_staffship_enterprise_teams_esm,
    :avoid_large_query_user_collabs_on_repos_candidate,
    :application_record_attribute_access_telemetry,
    :application_record_attribute_access_telemetry_route,
  ], only: :show
  preload_features USER_CONTENT_FEATURES

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Iam,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  def show
    render Discussions::BodyComponent.new(discussion: discussion, timeline: discussion_timeline), layout: false
  end

  private

  def discussion_timeline_render_context
    DiscussionTimeline::DiscussionBodyRenderContext.new(discussion,
      viewer: current_user,
      cap_filter: cap_filter,
    )
  end
end
