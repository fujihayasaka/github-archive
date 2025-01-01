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
    :remove_shelf_limited_paths,
    :preload_domain_by_name_and_owner,
    :domain_caching_repositories_repositories_by_name_and_owner,
    :bus_ids_exclude_billing_manager_valid_license,
    :enterprise_teams_crud,
    :restrict_discussions_convert_to_issue,
    :enterprise_teams_org_roles,
    :erp_preview_enterprise_teams_org_roles,
    :erp_staffship_enterprise_teams_org_roles,
    :use_billing_locked_rather_than_disabled,
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
