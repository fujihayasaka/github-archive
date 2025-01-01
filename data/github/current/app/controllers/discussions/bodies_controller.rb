# typed: true
# frozen_string_literal: true

class Discussions::BodiesController < Discussions::BaseController
  before_action :require_discussion
  preload_features [
    :all_repo_roles,
    :permission_enforcer_with_caching,
    :site_premium_support_redesign,
    :authenticated_avatars,
    :api_insights_rest,
    :owner_scoped_github_apps,
    :interaction_limit_kv_fallback,
    :stafftools_tenant_use_parameter,
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
