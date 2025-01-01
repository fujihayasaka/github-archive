# typed: true
# frozen_string_literal: true

class ActivityController < GitContentController
  include Repos::ActivityViewDependency # All the business logic for the controller lives in this helper
  include Repositories::Domain::Provider

  skip_before_action :try_to_expand_path

  sig { returns(String) }
  def self.react_bundle_name
    "activity"
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
    only: [:show, :index, :actors]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  def index
    payload = index_payload(pushed_after: RELIABLE_PUSH_DATA_TIME)

    render_react_app(
      title: "Activity · #{current_repository.name_with_display_owner}",
      payload: Repos::ReactPayload.camelize_keys(payload), # rubocop:disable GitHub/AvoidCamelizeKeys
      page_data: { selected_link: :repo_source },
      layout: "layouts/repository_with_container",
      ssr: false, # disabled until this app is ready for SSR
    )
  end

  def actors # rubocop:todo GitHub/UseRestfulActions
    # ensure time period is valid
    time_period = TIME_PERIODS.include?(params[:time_period]) ? params[:time_period] : "all"
    pushed_at = convert_time_period_to_time(time_period, RELIABLE_PUSH_DATA_TIME)
    pushers = repositories_domain.pushes.pushers_for(repository_id: current_repository.id, ref: current_ref, pushed_at: pushed_at).to_a

    payload = {
      actors: pushers.compact.map { |pusher| to_json_pusher(pusher) }
    }

    render json: Repos::ReactPayload.camelize_keys(payload) # rubocop:disable GitHub/AvoidCamelizeKeys
  end

  private

  def check_single_push_feature_flag
    feature = GitHub.flipper[:pushes_view_778_single_push]
    render_404 unless feature.enabled?(current_user) || feature.enabled?(current_repository) || feature.enabled?(current_repository.owner)
  end
end
