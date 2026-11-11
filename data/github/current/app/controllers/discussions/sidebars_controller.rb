# typed: true
# frozen_string_literal: true

class Discussions::SidebarsController < Discussions::BaseController
  before_action :require_discussion

  preload_features [
    :otel_rack_middleware,
    :emu_vss_business,
    :api_insights_rest,
    :owner_scoped_github_apps,
    :interaction_limit_kv_fallback,
    :stafftools_tenant_use_parameter,
    :reserved_domain,
    :restrict_discussions_convert_to_issue,
    :use_billing_locked_rather_than_disabled,
    :saml_satisfied_debug_logging,
    :enterprise_teams_killswitch,
    :avoid_large_query_user_collabs_on_repos_candidate,
    :remove_bill_mgr_internal_repo,
    :application_record_attribute_access_telemetry,
    :application_record_attribute_access_telemetry_route,
    :remote_cache_repo,
    :remote_cache_repo_rollout,
    :react_version_mismatch_detection,
  ]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Iam,
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
