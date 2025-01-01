# typed: true
# frozen_string_literal: true

class Discussions::BodiesController < Discussions::BaseController
  before_action :require_discussion
  preload_features [
    :bus_ids_exclude_billing_manager_valid_license,
    :site_premium_support_redesign,
    :api_insights_rest,
    :owner_scoped_github_apps,
    :interaction_limit_kv_fallback,
    :stafftools_tenant_use_parameter,
    :reserved_domain,
    :remove_shelf_limited_paths,
    :lifecycle_label_name_updates,
    :enterprise_teams_crud,
    :preload_domain_by_name_and_owner,
    :check_business_team_in_associated_repository_ids,
    :domain_caching_repositories_repositories_by_name_and_owner,
    :enterprise_teams_user_level_organization_visibility,
    :enterprise_teams_org_roles,
    :erp_preview_enterprise_teams_org_roles,
    :erp_staffship_enterprise_teams_org_roles,
    :use_billing_locked_rather_than_disabled,
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
