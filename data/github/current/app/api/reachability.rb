# typed: true
# frozen_string_literal: true

class Api::Reachability < Api::App
  include Api::App::AdvisoryPaginationHelpers

  get "/repositories/:repository_id/reachability/:commit_sha/advisories", operation_id: "reachability/advisories" do
    repo = find_repo!

    deliver_error!(404) unless GitHub.flipper[:reachability_api].enabled?(repo)

    control_access :get_repo,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deliver :reachability_advisories_hash, {}, nil
  end

  get "/repositories/:repository_id/reachability/:commit_sha/dependencies", operation_id: "reachability/dependencies" do
    repo = find_repo!

    deliver_error!(404) unless GitHub.flipper[:reachability_api].enabled?(repo)

    control_access :get_repo,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deliver :reachability_dependencies, {}, nil
  end
end
