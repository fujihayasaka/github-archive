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

    pushes, has_previous_page, has_next_page, cursor = fetch_pushes(
      **parse_params,
      pushed_after: RELIABLE_PUSH_DATA_TIME,
      per_page: pagination[:per_page]
    )

    @links.add_current({ after: cursor, before: nil, per_page: pagination[:per_page] == DEFAULT_PER_PAGE ? nil : pagination[:per_page] }, rel: "next") if has_next_page
    @links.add_current({ before: cursor, after: nil, per_page: pagination[:per_page] == DEFAULT_PER_PAGE ? nil : pagination[:per_page] }, rel: "prev") if has_previous_page

    deliver :push_hash, pushes
  end
end
