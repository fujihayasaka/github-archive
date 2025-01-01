# typed: true
# frozen_string_literal: true

class Discussions::SidebarsController < Discussions::BaseController
  before_action :require_discussion

  preload_features [
    :permission_enforcer_with_caching,
    :otel_rack_middleware,
    :emu_vss_business,
    :all_repo_roles,
    :authenticated_avatars,
    :api_insights_rest,
    :owner_scoped_github_apps,
    :interaction_limit_kv_fallback,
    :stafftools_tenant_use_parameter
  ]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show], optional: true

  def show
    discussion = T.must_because(self.discussion) { "#require_discussion ensures non-nil" }
    limited_participants = discussion.participants_for(current_user, limit: ONE_POINT_FIVE_TIMES_MAX_AVATARS)
    discussion.labels.load

    render Discussions::SidebarComponent.new(
      timeline: discussion_timeline,
      participants: limited_participants,
      events: discussion_timeline.events,
      org_param: org_param,
    ), layout: false
  end
end
