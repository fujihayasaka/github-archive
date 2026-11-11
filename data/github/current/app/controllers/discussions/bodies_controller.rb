# typed: true
# frozen_string_literal: true

class Discussions::BodiesController < Discussions::BaseController
  before_action :require_discussion
  preload_features [
    :api_insights_rest,
    :owner_scoped_github_apps,
    :interaction_limit_kv_fallback,
    :stafftools_tenant_use_parameter,
    :reserved_domain,
    :lifecycle_label_name_updates,
    :enterprise_teams_killswitch,
    :use_billing_locked_rather_than_disabled,
    :saml_satisfied_debug_logging,
    :enterprise_teams_killswitch,
    :avoid_large_query_user_collabs_on_repos_candidate,
    :application_record_attribute_access_telemetry,
    :application_record_attribute_access_telemetry_route,
    :remote_cache_repo,
    :remote_cache_repo_rollout,
    :report_missing_target_for_user_name_display_configuration,
    :react_version_mismatch_detection,
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
