# typed: true
# frozen_string_literal: true

class Discussions::TitlesController < Discussions::BaseController
  before_action :require_discussion
  preload_features [
    :otel_rack_middleware,
    :emu_vss_business,
    :html_pipeline_bad_emoji,
    :api_insights_rest,
    :owner_scoped_github_apps,
    :interaction_limit_kv_fallback,
    :stafftools_tenant_use_parameter,
    :reserved_domain,
    :use_billing_locked_rather_than_disabled,
    :saml_satisfied_debug_logging,
    :enterprise_teams_killswitch,
    :avoid_large_query_user_collabs_on_repos_candidate,
    :discussion_post_as_admin,
    :remove_bill_mgr_internal_repo,
    :application_record_attribute_access_telemetry,
    :application_record_attribute_access_telemetry_route,
    :scheduled_discussions,
    :remote_cache_repo,
    :force_user_name_display_name_and_handle,
    :report_missing_target_for_user_name_display_configuration,
    :react_version_mismatch_detection,
  ]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Iam,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  def show
    render(Discussions::StickyHeaderComponent.new(
      discussion:,
      timeline: discussion_timeline,
      parsed_discussions_query: parsed_discussions_query,
      org_param: org_param,
    ), layout: false)
  end
end
