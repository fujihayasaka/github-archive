# typed: true
# frozen_string_literal: true

class Discussions::FormActionsController < Discussions::BaseController
  before_action :require_discussion

  preload_features [
    :permission_enforcer_with_caching,
    :owner_scoped_github_apps,
    :stafftools_tenant_use_parameter
  ], only: :show
  preload_features [
    :emu_vss_business,
    :api_insights_rest
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
    render(Discussions::FormActionsComponent.new(
      timeline: discussion_timeline,
      is_inline_comment: false,
    ), layout: false)
  end
end
