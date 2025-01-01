# typed: true
# frozen_string_literal: true

class Discussions::HeaderReactionButtonsController < Discussions::BaseController
  before_action :require_discussion
  preload_features [
    :skip_open_graph_url_encoding,
    :otel_rack_middleware,
    :emu_vss_business,
    :oidc_policy_enforced,
    :api_insights_rest,
    :owner_scoped_github_apps,
    :stafftools_tenant_use_parameter,
    :remove_shelf_limited_paths,
    :preload_domain_by_name_and_owner,
  ]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  def show
    respond_to do |format|
      format.html do
        render Discussions::HeaderReactionButtonComponent.new(
          discussion_or_comment: discussion,
          timeline: discussion_timeline,
        ), layout: false
      end
    end
  end
end
