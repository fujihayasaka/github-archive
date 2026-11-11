# typed: strict
# frozen_string_literal: true

class Api::EnterpriseActionsDataStreamSinks < Api::Enterprise::App
  include Api::App::ActionsDataStreamSinksHelper
  include Api::App::TwirpHelpers

  get "/enterprises/:enterprise_id/actions/data-stream/sinks", operation_id: "actions/list-data-stream-sinks-for-enterprise" do
    enterprise = find_enterprise!
    deliver_error!(404) unless enterprise.feature_flag_enabled?(:actions_data_stream_ux, default: false)

    control_access :standard_authorization,
      resource: enterprise,
      permission: :read_enterprise_actions_data_stream_sinks,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    actions_data_stream_list_sinks!(owner: enterprise, owner_type: :enterprise)
  end

  get "/enterprises/:enterprise_id/actions/data-stream/sinks/by-name/:name", operation_id: "actions/get-data-stream-sink-by-name-for-enterprise" do
    enterprise = find_enterprise!
    deliver_error!(404) unless enterprise.feature_flag_enabled?(:actions_data_stream_ux, default: false)

    control_access :standard_authorization,
      resource: enterprise,
      permission: :read_enterprise_actions_data_stream_sinks,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    actions_data_stream_get_sink_by_name!(owner: enterprise, owner_type: :enterprise, name: params[:name])
  end

  get "/enterprises/:enterprise_id/actions/data-stream/sinks/:sink_id", operation_id: "actions/get-data-stream-sink-for-enterprise" do
    enterprise = find_enterprise!
    deliver_error!(404) unless enterprise.feature_flag_enabled?(:actions_data_stream_ux, default: false)

    control_access :standard_authorization,
      resource: enterprise,
      permission: :read_enterprise_actions_data_stream_sinks,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    actions_data_stream_get_sink!(owner: enterprise, owner_type: :enterprise, sink_id: params[:sink_id])
  end

  post "/enterprises/:enterprise_id/actions/data-stream/sinks", operation_id: "actions/create-data-stream-sink-for-enterprise", read_from_replicas: true do
    enterprise = find_enterprise!
    deliver_error!(404) unless enterprise.feature_flag_enabled?(:actions_data_stream_ux, default: false)

    control_access :standard_authorization,
      resource: enterprise,
      permission: :write_enterprise_actions_data_stream_sinks,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    actions_data_stream_create_sink!(owner: enterprise, owner_type: :enterprise)
  end

  patch "/enterprises/:enterprise_id/actions/data-stream/sinks/:sink_id", operation_id: "actions/update-data-stream-sink-for-enterprise", read_from_replicas: true do
    enterprise = find_enterprise!
    deliver_error!(404) unless enterprise.feature_flag_enabled?(:actions_data_stream_ux, default: false)

    control_access :standard_authorization,
      resource: enterprise,
      permission: :write_enterprise_actions_data_stream_sinks,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    actions_data_stream_update_sink!(owner: enterprise, owner_type: :enterprise, sink_id: params[:sink_id])
  end

  delete "/enterprises/:enterprise_id/actions/data-stream/sinks/:sink_id", operation_id: "actions/delete-data-stream-sink-for-enterprise", read_from_replicas: true do
    enterprise = find_enterprise!
    deliver_error!(404) unless enterprise.feature_flag_enabled?(:actions_data_stream_ux, default: false)

    control_access :standard_authorization,
      resource: enterprise,
      permission: :write_enterprise_actions_data_stream_sinks,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    actions_data_stream_delete_sink!(owner: enterprise, owner_type: :enterprise, sink_id: params[:sink_id])
  end

  post "/enterprises/:enterprise_id/actions/data-stream/sinks/test-connection", operation_id: "actions/test-data-stream-sink-new-for-enterprise", read_from_replicas: true do
    enterprise = find_enterprise!
    deliver_error!(404) unless enterprise.feature_flag_enabled?(:actions_data_stream_ux, default: false)

    control_access :standard_authorization,
      resource: enterprise,
      permission: :write_enterprise_actions_data_stream_sinks,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    actions_data_stream_test_sink_new!(owner: enterprise, owner_type: :enterprise)
  end

  post "/enterprises/:enterprise_id/actions/data-stream/sinks/:sink_id/test-connection", operation_id: "actions/test-data-stream-sink-for-enterprise", read_from_replicas: true do
    enterprise = find_enterprise!
    deliver_error!(404) unless enterprise.feature_flag_enabled?(:actions_data_stream_ux, default: false)

    control_access :standard_authorization,
      resource: enterprise,
      permission: :write_enterprise_actions_data_stream_sinks,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    actions_data_stream_test_sink!(owner: enterprise, owner_type: :enterprise, sink_id: params[:sink_id])
  end
end
