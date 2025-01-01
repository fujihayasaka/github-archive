# typed: true
# frozen_string_literal: true

class Api::RepositoryActivities < Api::App
  include Api::App::ContentHelpers, RepositoriesHelper
  include Repos::ActivityViewDependency # All the business logic for the controller lives in this helper

  # List activities (for now only pushes) for a repo
  get "/repositories/:repository_id/activity", operation_id: "repos/list-activities" do
    control_access :list_activities,
      resource: current_repository,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    parsed_params = parse_params

    pushes_collection = fetch_pushes_from_domain(
      repository_id: current_repository.id,
      ref: current_ref,
      per_page: pagination[:per_page],
      sort: parsed_params[:sort],
      activity_type: parsed_params[:activity_type],
      actor: parsed_params[:actor],
      actor_filter_present: parsed_params[:actor_filter_present],
      time_period: parsed_params[:time_period],
      pushed_after: RELIABLE_PUSH_DATA_TIME,
      before: parsed_params[:before],
      after: parsed_params[:after]
    )

    @links.add_current({ after: pushes_collection.end_cursor, before: nil, per_page: pagination[:per_page] == DEFAULT_PER_PAGE ? nil : pagination[:per_page] }, rel: "next") if pushes_collection.has_next_page?
    @links.add_current({ before: pushes_collection.start_cursor, after: nil, per_page: pagination[:per_page] == DEFAULT_PER_PAGE ? nil : pagination[:per_page] }, rel: "prev") if pushes_collection.has_previous_page?

    deliver :push_hash, pushes_collection.to_a
  end
end
