# typed: true
# frozen_string_literal: true

class Api::RepositoryEventDispatches < Api::App
  include ReceiveSchemaWithOpenApi

  # Trigger an event for running a Repository Task (launch flow file)
  post "/repositories/:repository_id/dispatches", operation_id: "repos/create-dispatch-event" do
    repo = find_repo!

    control_access :create_repo_dispatch,
      repo: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    data = receive_with_schema("repository-dispatch", "create")

    client_payload = data["client_payload"]
    # Apply the same check we use for `deployment` payloads
    if client_payload && client_payload.to_json.length > MYSQL_TEXT_FIELD_LIMIT
      deliver_error! 422, message: "client_payload is too large."
    end

    repo.dispatch_event(
      current_user.id,
      data["event_type"],
      client_payload,
    )
    deliver_empty(status: 204)
  end

end
