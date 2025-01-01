# typed: true
# frozen_string_literal: true

class Discussions::TitlesController < Discussions::BaseController
  before_action :require_discussion
  preload_features [
    :otel_rack_middleware,
    :emu_vss_business,
    :html_pipeline_bad_emoji,
    :authenticated_avatars,
    :api_insights_rest,
    :owner_scoped_github_apps,
    :interaction_limit_kv_fallback,
    :stafftools_tenant_use_parameter,
    :reserved_domain,
    :remove_shelf_limited_paths,
    :preload_domain_by_name_and_owner,
  ]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  def show
    render(Discussions::TitleComponent.new(
      discussion:,
      timeline: discussion_timeline,
      parsed_discussions_query: parsed_discussions_query,
      org_param: org_param,
    ), layout: false)
  end
end
