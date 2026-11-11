# typed: strict
# frozen_string_literal: true

class Api::OrganizationActionsDataStreamSinks < Api::App
  include Api::App::ActionsDataStreamSinksHelper
  include Api::App::TwirpHelpers

  get "/organizations/:organization_id/actions/data-stream/sinks", operation_id: "actions/list-data-stream-sinks-for-org" do
    org = find_org!
    deliver_error!(404) unless org.feature_flag_enabled?(:actions_data_stream_ux, default: false)

    control_access :standard_authorization,
      resource: org,
      permission: :read_organization_actions_data_stream_sinks,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_ACTIONS_READ_DATA_STREAM_SINKS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    actions_data_stream_list_sinks!(owner: org, owner_type: :organization)
  end

  get "/organizations/:organization_id/actions/data-stream/sinks/by-name/:name", operation_id: "actions/get-data-stream-sink-by-name-for-org" do
    org = find_org!
    deliver_error!(404) unless org.feature_flag_enabled?(:actions_data_stream_ux, default: false)

    control_access :standard_authorization,
      resource: org,
      permission: :read_organization_actions_data_stream_sinks,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_ACTIONS_READ_DATA_STREAM_SINKS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    actions_data_stream_get_sink_by_name!(owner: org, owner_type: :organization, name: params[:name])
  end

  get "/organizations/:organization_id/actions/data-stream/sinks/:sink_id", operation_id: "actions/get-data-stream-sink-for-org" do
    org = find_org!
    deliver_error!(404) unless org.feature_flag_enabled?(:actions_data_stream_ux, default: false)

    control_access :standard_authorization,
      resource: org,
      permission: :read_organization_actions_data_stream_sinks,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_ACTIONS_READ_DATA_STREAM_SINKS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    actions_data_stream_get_sink!(owner: org, owner_type: :organization, sink_id: params[:sink_id])
  end

  post "/organizations/:organization_id/actions/data-stream/sinks", operation_id: "actions/create-data-stream-sink-for-org", read_from_replicas: true do
    org = find_org!
    deliver_error!(404) unless org.feature_flag_enabled?(:actions_data_stream_ux, default: false)

    control_access :standard_authorization,
      resource: org,
      permission: :write_organization_actions_data_stream_sinks,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_ACTIONS_WRITE_DATA_STREAM_SINKS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    actions_data_stream_create_sink!(owner: org, owner_type: :organization)
  end

  patch "/organizations/:organization_id/actions/data-stream/sinks/:sink_id", operation_id: "actions/update-data-stream-sink-for-org", read_from_replicas: true do
    org = find_org!
    deliver_error!(404) unless org.feature_flag_enabled?(:actions_data_stream_ux, default: false)

    control_access :standard_authorization,
      resource: org,
      permission: :write_organization_actions_data_stream_sinks,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_ACTIONS_WRITE_DATA_STREAM_SINKS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    actions_data_stream_update_sink!(owner: org, owner_type: :organization, sink_id: params[:sink_id])
  end

  delete "/organizations/:organization_id/actions/data-stream/sinks/:sink_id", operation_id: "actions/delete-data-stream-sink-for-org", read_from_replicas: true do
    org = find_org!
    deliver_error!(404) unless org.feature_flag_enabled?(:actions_data_stream_ux, default: false)

    control_access :standard_authorization,
      resource: org,
      permission: :write_organization_actions_data_stream_sinks,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_ACTIONS_WRITE_DATA_STREAM_SINKS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    actions_data_stream_delete_sink!(owner: org, owner_type: :organization, sink_id: params[:sink_id])
  end

  post "/organizations/:organization_id/actions/data-stream/sinks/test-connection", operation_id: "actions/test-data-stream-sink-new-for-org", read_from_replicas: true do
    org = find_org!
    deliver_error!(404) unless org.feature_flag_enabled?(:actions_data_stream_ux, default: false)

    control_access :standard_authorization,
      resource: org,
      permission: :write_organization_actions_data_stream_sinks,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_ACTIONS_WRITE_DATA_STREAM_SINKS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    actions_data_stream_test_sink_new!(owner: org, owner_type: :organization)
  end

  post "/organizations/:organization_id/actions/data-stream/sinks/:sink_id/test-connection", operation_id: "actions/test-data-stream-sink-for-org", read_from_replicas: true do
    org = find_org!
    deliver_error!(404) unless org.feature_flag_enabled?(:actions_data_stream_ux, default: false)

    control_access :standard_authorization,
      resource: org,
      permission: :write_organization_actions_data_stream_sinks,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_ACTIONS_WRITE_DATA_STREAM_SINKS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    actions_data_stream_test_sink!(owner: org, owner_type: :organization, sink_id: params[:sink_id])
  end
end
