# typed: true
# frozen_string_literal: true

class Discussions::CommentCountsController < Discussions::BaseController
  before_action :require_discussion

  preload_features [
    :otel_rack_middleware,
    :emu_vss_business,
    :oidc_policy_enforced,
    :api_insights_rest,
    :owner_scoped_github_apps,
    :stafftools_tenant_use_parameter,
    :remove_shelf_limited_paths,
    :preload_domain_by_name_and_owner,
    :domain_caching_repositories_repositories_by_name_and_owner,
    :use_billing_locked_rather_than_disabled,
  ]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  def show
    render Discussions::CommentCountComponent.new(
      discussion: discussion,
      repository: current_repository,
    ), layout: false
  end
end
