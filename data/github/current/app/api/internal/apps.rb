# typed: strict
# frozen_string_literal: true

class Api::Internal::Apps < Api::Internal
  include ReceiveSchemaWithOpenApi

  sig { returns(T::Boolean) }
  def externally_accessible?
    true
  end

  sig { returns(T::Boolean) }
  def require_request_hmac?
    true
  end

  sig { returns(T::Boolean) }
  def authenticated_for_private_mode?
    true
  end

  # request:
  # here's what I know
  # { apps: [
  #     { global_relay_id: "", fingerprint: ""}
  #   ]
  # }
  # response:
  # here's what you need to know
  # { apps: [
  #     { global_relay_id: "", fingerprint: "" }
  #   ]
  # }
  post "/internal/apps/proxima_app_synchronizations", operation_id: "apps/list-proxima-app-synchronizations" do
    data = receive_with_openapi
    syncable_apps = ProximaApp.synchronization_from(data["apps"], data["party"]).syncable

    response = {
      apps: syncable_apps.map { |app| app.current_state_hash }
    }

    deliver_raw response
  end

  # request:
  #  { global_relay_id: "" }
  #
  # response:
  # { manifest:
  #      global_relay_id: "",
  #      fingerprint: ""
  #      settings: {
  #       .
  #       .
  #       .
  #      }
  # }
  get "/internal/apps/proxima_app_manifest/:global_relay_id", operation_id: "apps/get-proxima-app-manifest" do
    # We need this to validate the query params
    receive_with_openapi

    app = ProximaApp.app_from_global_id(params["global_relay_id"])
    deliver_error!(404) unless app

    deliver :internal_app_manifest_response, app
  end
end
