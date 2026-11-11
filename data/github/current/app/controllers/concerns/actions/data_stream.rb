# typed: true
# frozen_string_literal: true

# Shared concern for Actions Data Stream settings controllers.
# Provides twirp client wrappers for sink CRUD operations.
# Include in both the org and enterprise controllers.
module Actions::DataStream
  extend ActiveSupport::Concern
  extend T::Helpers

  abstract!

  requires_ancestor { ApplicationController }

  included do
    include ApplicationController::VerifiedFetchDependency
    include ApplicationController::JsonDependency

    T.bind(self, T.class_of(ApplicationController))

    before_action :login_required
    before_action :data_stream_admin_required
    before_action :data_stream_feature_flag_enabled?

    T.unsafe(self).allow_verified_fetch only: [:create, :update, :destroy, :pause, :resume, :test_connection]
    before_action :try_parse_json_params, only: [:create, :update, :test_connection]
  end

  # --- actions ---

  def index
    result = sink_client.list_sinks(
      owner_type: data_stream_owner_type,
      owner_id: data_stream_owner_id,
    )

    fetch_error = false
    sinks = if result.call_succeeded? && result.value
      serialize_sinks(result.value.sinks)
    else
      fetch_error = true
      []
    end

    payload_obj = build_index_payload(sinks, fetch_error:)

    render_react_app(
      payload: payload_obj,
      title: "Data Streams · #{data_stream_entity.display_login}",
      layout: data_stream_layout,
      page_data: data_stream_page_data,
      **data_stream_extra_render_options,
    )
  end

  def show
    result = sink_client.get_sink(
      owner_type: data_stream_owner_type,
      owner_id: data_stream_owner_id,
      id: params[:id],
    )

    unless result.call_succeeded?
      render_404
      return
    end

    sink = serialize_sink(result.value.sink)
    payload_obj = build_edit_payload(sink)

    render_react_app(
      payload: payload_obj,
      title: "Edit Data Stream · #{data_stream_entity.display_login}",
      layout: data_stream_layout,
      page_data: data_stream_page_data,
      **data_stream_extra_render_options,
    )
  end

  def new_sink
    payload_obj = build_new_payload

    render_react_app(
      payload: payload_obj,
      title: "New Data Stream · #{data_stream_entity.display_login}",
      layout: data_stream_layout,
      page_data: data_stream_page_data,
      **data_stream_extra_render_options,
    )
  end

  SINK_TYPE_MAP = {
    "azure_kusto" => :SINK_TYPE_AZURE_KUSTO,
    "azure_blob" => :SINK_TYPE_AZURE_BLOB,
    "s3" => :SINK_TYPE_S3,
    "azure_event_hub" => :SINK_TYPE_AZURE_EVENT_HUB,
    "aws_firehose" => :SINK_TYPE_AWS_FIREHOSE,
  }.freeze

  SINK_TYPE_REVERSE_MAP = SINK_TYPE_MAP.invert.freeze

  SINK_STATUS_MAP = {
    "active" => :SINK_STATUS_ACTIVE,
    "paused" => :SINK_STATUS_PAUSED,
    "disabled" => :SINK_STATUS_DISABLED,
    "error" => :SINK_STATUS_ERROR,
  }.freeze

  SINK_STATUS_REVERSE_MAP = SINK_STATUS_MAP.invert.freeze

  HEALTH_STATUS_REVERSE_MAP = {
    HEALTH_STATUS_HEALTHY: "healthy",
    HEALTH_STATUS_DEGRADED: "degraded",
    HEALTH_STATUS_UNHEALTHY: "unhealthy",
    HEALTH_STATUS_INVALID: "invalid",
  }.freeze

  def create
    name = params[:name]
    sink_type = params[:sink_type]
    config = params[:config]

    if name.blank? || sink_type.blank? || config.blank?
      render json: { errors: "Name, sink type, and configuration are required." }, status: :unprocessable_entity
      return
    end

    proto_sink_type = SINK_TYPE_MAP[sink_type]
    unless proto_sink_type
      render json: { errors: "Unknown sink type: #{sink_type}" }, status: :unprocessable_entity
      return
    end

    result = sink_client.create_sink(
      owner_type: data_stream_owner_type,
      owner_id: data_stream_owner_id,
      name: name,
      sink_type: proto_sink_type,
      config: config_to_proto(config),
    )

    if result.call_succeeded?
      render json: { payload: { redirect_url: data_stream_base_path } }, status: :created
    else
      render json: { errors: result.options[:message] || "Failed to create stream." }, status: result.status
    end
  end

  def update
    update_params = {}
    update_params[:name] = params[:name] if params[:name].present?
    update_params[:config] = config_to_proto(params[:config]) if params[:config].present?

    if params[:status].present?
      proto_status = SINK_STATUS_MAP[params[:status]]
      unless proto_status
        render json: { errors: "Unknown status: #{params[:status]}" }, status: :unprocessable_entity
        return
      end
      update_params[:status] = proto_status
    end

    result = sink_client.update_sink(
      owner_type: data_stream_owner_type,
      owner_id: data_stream_owner_id,
      id: params[:id],
      **update_params,
    )

    if result.call_succeeded?
      render json: { payload: { redirect_url: data_stream_base_path } }
    else
      render json: { errors: result.options[:message] || "Failed to update stream." }, status: result.status
    end
  end

  def destroy
    result = sink_client.delete_sink(
      owner_type: data_stream_owner_type,
      owner_id: data_stream_owner_id,
      id: params[:id],
    )

    if result.call_succeeded?
      render json: { payload: { redirect_url: data_stream_base_path } }
    else
      render json: { errors: result.options[:message] || "Failed to delete stream." }, status: result.status
    end
  end

  def pause
    result = sink_client.update_sink(
      owner_type: data_stream_owner_type,
      owner_id: data_stream_owner_id,
      id: params[:id],
      status: :SINK_STATUS_PAUSED,
    )

    if result.call_succeeded?
      render json: { ok: true }
    else
      render json: { errors: result.options[:message] || "Failed to pause stream." }, status: result.status
    end
  end

  def resume
    result = sink_client.update_sink(
      owner_type: data_stream_owner_type,
      owner_id: data_stream_owner_id,
      id: params[:id],
      status: :SINK_STATUS_ACTIVE,
    )

    if result.call_succeeded?
      render json: { ok: true }
    else
      render json: { errors: result.options[:message] || "Failed to resume stream." }, status: result.status
    end
  end

  def test_connection
    test_params = {}

    if params[:sink_id].present?
      test_params[:sink_id] = params[:sink_id]
    elsif params[:sink_type].present? && params[:config].present?
      proto_sink_type = SINK_TYPE_MAP[params[:sink_type]]
      unless proto_sink_type
        render json: { success: false, error_message: "Unknown sink type: #{params[:sink_type]}" }, status: :unprocessable_entity
        return
      end

      test_params[:create_sink_request] = {
        owner_type: data_stream_owner_type,
        owner_id: data_stream_owner_id,
        name: params[:name].presence || "test-connection",
        sink_type: proto_sink_type,
        config: config_to_proto(params[:config]),
      }
    else
      render json: { success: false, error_message: "Either sink_id or sink_type and config are required." }, status: :unprocessable_entity
      return
    end

    result = sink_client.test_sink(
      owner_type: data_stream_owner_type,
      owner_id: data_stream_owner_id,
      **test_params,
    )

    if result.call_succeeded?
      resp = result.value
      render json: {
        success: resp.success,
        error_message: resp.error_message.presence || "",
        status_code: resp.status_code,
        latency_ms: resp.latency_ms,
      }
    else
      render json: {
        success: false,
        error_message: result.options[:message] || "Failed to test connection.",
        status_code: 0,
        latency_ms: 0,
      }, status: result.status
    end
  end

  private

  # --- abstract interface that including controllers must implement ---

  sig { abstract.returns(T.any(Organization, Business)) }
  def data_stream_entity; end

  sig { abstract.returns(Integer) }
  def data_stream_owner_id; end

  sig { abstract.returns(Symbol) }
  def data_stream_owner_type; end

  sig { abstract.returns(String) }
  def data_stream_base_path; end

  sig { abstract.void }
  def data_stream_admin_required; end

  def sink_client
    ActionsDataStream::Twirp.sink_client
  end

  def config_to_proto(config)
    hash = config.respond_to?(:to_unsafe_h) ? config.to_unsafe_h : config.to_h
    Google::Protobuf::Struct.from_hash(hash)
  end

  def serialize_sinks(sinks)
    return [] if sinks.nil?

    sinks.map { |sink| serialize_sink(sink) }
  end

  def serialize_sink(sink)
    data = {
      id: sink.id,
      name: sink.name,
      sinkType: SINK_TYPE_REVERSE_MAP[sink.sink_type] || sink.sink_type.to_s,
      status: SINK_STATUS_REVERSE_MAP[sink.status] || sink.status.to_s,
      config: sink.config.to_h,
    }

    if sink.sink_health
      health = sink.sink_health
      data[:healthStatus] = HEALTH_STATUS_REVERSE_MAP[health.health_status] || health.health_status.to_s
      data[:lastError] = health.last_error if health.last_error.present?
      data[:lastSuccessAt] = health.last_success_at&.to_time&.iso8601
      data[:lastFailureAt] = health.last_failure_at&.to_time&.iso8601
    end

    data
  end

  def data_stream_feature_flag_enabled?
    render_404 unless FeatureFlag.vexi.enabled?(:actions_data_stream_ux, data_stream_entity, default: false)
  end

  sig { abstract.returns(String) }
  def data_stream_layout; end

  sig { abstract.returns(Symbol) }
  def data_stream_selected_link; end

  sig { abstract.returns(T::Hash[Symbol, T.untyped]) }
  def data_stream_extra_render_options; end

  sig { abstract.returns(T::Hash[Symbol, T.untyped]) }
  def data_stream_page_data; end

  # --- payload builders (overridable per-controller) ---

  def owner_claim_subject
    type_label = data_stream_owner_type == :OWNER_TYPE_ENTERPRISE ? "enterprise" : "organization"
    "actions-data-stream:#{type_label}/#{data_stream_owner_id}"
  end

  def build_index_payload(sinks, fetch_error: false)
    payload = {
      entityLogin: data_stream_entity.display_login,
      sinks: sinks,
      createPath: "#{data_stream_base_path}/new",
      basePath: data_stream_base_path,
      testConnectionPath: "#{data_stream_base_path}/test-connection",
      subjectClaim: owner_claim_subject,
    }
    payload[:fetchError] = true if fetch_error
    payload
  end

  def build_edit_payload(sink)
    {
      entityLogin: data_stream_entity.display_login,
      sink: sink,
      updatePath: "#{data_stream_base_path}/#{sink[:id]}",
      indexPath: data_stream_base_path,
      testConnectionPath: "#{data_stream_base_path}/test-connection",
    }
  end

  def build_new_payload
    {
      entityLogin: data_stream_entity.display_login,
      createPath: data_stream_base_path,
      indexPath: data_stream_base_path,
      testConnectionPath: "#{data_stream_base_path}/test-connection",
      subjectClaim: owner_claim_subject,
    }
  end
end
