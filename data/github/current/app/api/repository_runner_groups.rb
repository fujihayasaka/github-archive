# typed: true
# frozen_string_literal: true

require "actions-runner-admin"

class Api::RepositoryRunnerGroups < Api::App
  include ReceiveSchemaWithOpenApi
  include Api::App::TwirpHelpers
  include Actions::RunnerGroupsHelper
  include Api::App::HostedRunnersHelper
  include Api::App::ActionsRunnersHelper

  # List runner groups
  get "/repositories/:repository_id/actions/runner-groups", operation_id: :internal do
    deliver_error! 404 unless repo_runners_enabled?

    repo = find_repo!

    deliver_error!(404) unless GitHub.flipper[:actions_runners_use_runner_admin_service].enabled?(repo)
    deliver_error! 403, message: "Forbidden", errors: "Repository level self-hosted runners are disabled on this repository" if repo.repo_self_hosted_runners_disabled_by_owner?

    attempt_runner_registration_login(repo)

    control_access :read_admin_actions,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    runner_admin_client = GitHub.build_runner_admin_client(repo)
    resp = handle_twirp_errors do
      runner_admin_client.list_runner_groups(owner: repo)
    end

    validate_runner_groups_response!(resp&.runner_groups)
    runner_groups = paginate_rel(resp&.runner_groups.map { |runner_group| runner_group })

    deliver :actions_repo_runner_groups_hash, {
      runner_groups: runner_groups,
      total_count: runner_groups.total_entries,
      repo: repo,
    }
  end
end
