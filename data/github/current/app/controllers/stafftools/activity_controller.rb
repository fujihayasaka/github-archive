# typed: true
# frozen_string_literal: true

class Stafftools::ActivityController < StafftoolsController
  extend T::Sig

  include Repos::ActivityViewDependency # All the business logic for the controller lives in this helper
  include Repositories::Domain::Provider

  before_action :ensure_repo_exists

  sig { returns(String) }
  def self.react_bundle_name
    "stafftools-activity"
  end

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::RepositoriesPushes,
    ApplicationRecord::Configurations,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    only: [:index, :actors]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  def index
    payload = index_payload

    render_react_app(
      title: "Activity · #{current_repository.name_with_owner}",
      payload: Repos::ReactPayload.camelize_keys(payload), # rubocop:disable GitHub/AvoidCamelizeKeys
      layout: "layouts/stafftools/repository/security",
      ssr: false, # disabled until this app is ready for SSR
    )
  end

  def actors # rubocop:todo GitHub/UseRestfulActions
    # ensure time period is valid
    time_period = TIME_PERIODS.include?(params[:time_period]) ? params[:time_period] : "all"
    pushed_at = convert_time_period_to_time(time_period, nil)
    pushers = repositories_domain.pushes.pushers_for(repository: current_repository, ref: current_ref, pushed_at: pushed_at).to_a

    payload = {
      actors: pushers.compact.map { |pusher| to_json_pusher(pusher) }
    }

    render json: Repos::ReactPayload.camelize_keys(payload) # rubocop:disable GitHub/AvoidCamelizeKeys
  end

  private

  # Public controller inherits this method from `AbstractRepositoryController`.
  # But we cannot inherit from it in Stafftools.
  # So re-defining this method here explicitly.
  memoize def commit_sha
    current_repository.ref_to_sha(tree_name)
  end
end
