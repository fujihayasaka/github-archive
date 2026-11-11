# typed: true
# frozen_string_literal: true

class Api::RepositoryEventDispatches < Api::App
  include ReceiveSchemaWithOpenApi

  # Trigger an event for running a Repository Task (launch flow file)
  post "/repositories/:repository_id/dispatches", operation_id: "repos/create-dispatch-event", read_from_replicas: true do
    repo = find_repo!

    control_access :create_repo_dispatch,
      repo: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    data = receive_with_schema("repository-dispatch", "create")

    client_payload = data["client_payload"]
    if FeatureFlag.vexi.enabled?(:repository_dispatch_validate_client_payload_json, repo, default: false)
      if client_payload
        # Normally our JSON parsers will raise an exception for nesting depth > 256, but we know that
        # the client payload will be wrapped in 2 more levels of nesting downstream, so we actually want
        # to check for nesting depth > 254 here to fail fast.
        wrapped_client_payload = {
          payload: {
            client_payload: client_payload,
          },
        }

        begin
          # Pass dangerously_allow_all_keys so that if encoding hits invalid UTF-8, the raw client
          # payload is NOT dumped into logs (see lib/github/json.rb, scrub_invalid_utf8_hack).
          # The "dangerous" guard itself is about leaking sensitive ActiveRecord attributes when
          # serializing a model, but wrapped_client_payload is a plain Hash of parsed
          # JSON primitives with no AR objects, so that guard is not relevant here.
          encoded_client_payload = wrapped_client_payload.to_json(dangerously_allow_all_keys: true)
        rescue Yajl::EncodeError, JSON::NestingError
          deliver_error! 422, message: "client_payload is invalid JSON."
        end

        if encoded_client_payload.bytesize > MYSQL_TEXT_FIELD_LIMIT
          deliver_error! 422, message: "client_payload is too large."
        end
      end
    else
      # Apply the same check we use for `deployment` payloads
      if client_payload && client_payload.to_json.length > MYSQL_TEXT_FIELD_LIMIT
        deliver_error! 422, message: "client_payload is too large."
      end
    end

    repo.dispatch_event(
      current_user.id,
      data["event_type"],
      client_payload,
    )
    deliver_empty(status: 204)
  end
end
