# typed: true
# frozen_string_literal: true

class Api::Internal::PorterCallbacks < Api::Internal

  # http://en.wikipedia.org/wiki/List_of_The_Walking_Dead_characters
  require_api_semantic_version "eugene"

  put "/internal/porter/repositories/:repository_id/importing", operation_id: :internal do
    @route_owner = "@github/data-liberation"
    control_access :set_import_state, resource: current_repo, allow_integrations: false, allow_user_via_granular_actor: false

    ImportExport.domain.importing_started!(current_repo)

    deliver_empty status: 204
  end

  patch "/internal/porter/repositories/:repository_id/importing", operation_id: :internal do
    @route_owner = "@github/data-liberation"
    control_access :receive_import_status, resource: current_repo, allow_integrations: false, allow_user_via_granular_actor: false
    data = receive(Hash)

    payload = {
      timestamp: Time.now.to_i,
      reason: "Import to #{current_repo.name_with_owner} is #{data["status"] || "updated"}",
    }
    import = RepositorySourceImport.new(repository: current_repo, user: current_user)
    import.import_status_hash = data
    if import.lfs_opt_needed?
      payload[:redirect_to] = "#{current_repo.permalink}/import/large_files"
    end
    channel = GitHub::WebSocket::Channels.source_import(current_repo)
    GitHub::WebSocket.notify_repository_channel current_repo, channel, payload

    deliver_empty status: 204
  end

  delete "/internal/porter/repositories/:repository_id/importing", operation_id: :internal do
    @route_owner = "@github/data-liberation"
    control_access :set_import_state, resource: current_repo, allow_integrations: false, allow_user_via_granular_actor: false

    ImportExport.domain.importing_stopped!(current_repo)

    Porter::Notifier.new(
      porter_data:      { "message_type" => "import_cancelled" },
      repository:       current_repo,
      user:             current_user,
      notify_by_mail: false,
    ).notify_if_complete

    deliver_empty status: 204
  end

  post "/internal/porter/repositories/:repository_id/messages", operation_id: :internal do
    @route_owner = "@github/data-liberation"
    control_access :send_message, resource: current_repo, allow_integrations: false, allow_user_via_granular_actor: false

    data = receive(Hash)
    notifier = Porter::Notifier.new(
      porter_data: data,
      repository:  current_repo,
      user:        current_user,
    )

    if notifier.notify_if_complete
      GlobalInstrumenter.instrument("repository.import_completed", {
        repository: current_repo,
        actor: current_user,
        completed_status: notifier.completed_status
      })
      deliver_empty status: 204
    else
      deliver_error 422
    end
  end
end
