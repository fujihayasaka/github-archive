# typed: true
# frozen_string_literal: true

class Api::Admin::ElmMigrationState < Api::Admin
  # Update the ELM (Enterprise Live Migrations) banner state on a source repository.
  #
  # This endpoint is called by elm-exporter at key lifecycle moments so that the
  # source GHES instance can display an accurate, phase-specific migration banner:
  #
  #   started / resources_sent   → editable notice (migration in progress)
  #   locked / live_updates_sent → read-only notice (cutover has begun)
  #   complete                   → done notice with link to destination repo
  post "/admin/repos/:owner/:repo/elm-migration-state", operation_id: "enterprise-admin/set-elm-migration-state", read_from_replicas: true do # rubocop:todo GitHub/ControlAccess
    deliver_error!(404) unless GitHub.enterprise_only_api_enabled?

    data = receive(Hash)

    state = data["state"]
    destination_url = data["destination_url"]

    unless Configurable::RepositoryElmMigrationState::ALL_STATES.include?(state)
      deliver_error! 422, message: "Invalid state: must be one of #{Configurable::RepositoryElmMigrationState::ALL_STATES.join(", ")}"
    end

    owner_login = params[:owner]
    repo_name   = params[:repo]

    repo = Repository.nwo("#{owner_login}/#{repo_name}")
    deliver_error! 404 unless repo

    begin
      ElmMigrationStateConfig.new(repo).set_elm_migration_state(state, destination_url: destination_url)
    rescue ArgumentError => e
      deliver_error! 422, message: e.message
    end

    deliver_empty(status: 204)
  end
end
