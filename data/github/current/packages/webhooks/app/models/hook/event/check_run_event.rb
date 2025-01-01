# typed: true
# frozen_string_literal: true

class Hook::Event::CheckRunEvent < Hook::Event
  include Hook::Event::ChecksDependency

  supports_targets(*DEFAULT_TARGETS)
  description "Check run is created, requested, rerequested, or completed."

  event_attr :check_run_id, :action, required: true
  # specific_app_only lets us send this hook to a specific app instead of any app subscribed to these events
  event_attr :specific_app_only, :actor_id, :requested_action

  def check_run
    return @_models[:check_run] if @_models[:check_run]

    record_query_counts "prehydration_check_run_event_queries" do
      @check_run ||= begin
        run = Checks.domain.check_runs.unsafe_for_id(check_run_id)
        raise ActiveRecord::RecordNotFound unless run
        run
      end
    end
  end

  def check_suite
    @check_suite ||= check_run.check_suite
  end

  def initialize_primary_resource
    # explicit column filtering to ensure even model is resilient to migrations and database changes
    # https://github.com/github/availability/issues/2669
    return unless super
    valid_keys = CheckRun.column_names
    primary_resource_data.filter! do |key|
      valid_keys.any? { |valid_key| key.to_s == valid_key }
    end
    @check_run = CheckRun.new(primary_resource_data)
  end

  def initialize_from_attachment_data
    return unless attributes[:attachment_data].present?

    check_run = Events::Domain::Tier1EventAttachmentDecoder.new(
      Hydro::Schemas::Github::EventPayloadAttachment::V0::CheckRunAttachment,
      attributes[:attachment_data]
    ).decode(:check_run, CheckRun)
    @check_run = check_run
  end

  def tier1_event
    return nil unless check_run
    return @tier1_event if defined?(@tier1_event)

    # Build the attachment with CheckRun data
    attachment_builder = Events::Domain::Tier1EventAttachmentBuilder.new(
      Hydro::Schemas::Github::EventPayloadAttachment::V0::CheckRunAttachment
    )
    attachment_builder.model(:check_run, check_run)
    hydro_attachment = attachment_builder.build

    # Wrap the protobuf attachment in Events::EventAttachment
    event_attachment = Events::EventAttachment.new(
      type_url: "type.googleapis.com/hydro.schemas.github.event_payload_attachment.v0.CheckRunAttachment",
      message: T.unsafe(Hydro::Schemas::Github::EventPayloadAttachment::V0::CheckRunAttachment).encode(hydro_attachment)
    )

    event_action = :"EVENT_ACTION_#{action.to_s.upcase}"

    requested_action_arg = Hydro::Schemas::Github::HookEventAttributes::V0::Entities::RequestedAction.new(identifier: requested_action[:identifier].to_s) if requested_action && requested_action[:identifier]

    # Build the tier 1 event
    builder = Events::Domain::Tier1EventBuilder.new
      .action(event_action)
      .event_type(:EVENT_TYPE_CHECK_RUN)
      .guid(guid)
      .primary_entity(check_run)
      .repository(target_repository)
      .organization(target_organization)
      .business(target_business)
      .actor(actor)
      .attachment(event_attachment)
      .hook_event_attributes(Hydro::Schemas::Github::HookEventAttributes::V0::CheckRunEventAttributes.new({
        action: action.to_s,
        actor_id: Events::ProtobufsHelper.wrap_value(Google::Protobuf::Int64Value, actor_id),
        check_run_id: check_run_id,
        requested_action: requested_action_arg,
        specific_app_only: Events::ProtobufsHelper.wrap_value(Google::Protobuf::BoolValue, specific_app_only)
      }))

    builder = builder.single_integration_webhooks_delivery_scope(
      check_run.check_suite.github_app.id,
      !FeatureFlag.vexi.enabled?(:checks_request_hook_when_permissions_and_subscription, check_run.check_suite, default: false)
    ) if specific_app_only

    @tier1_event ||= builder.build_tier_1_event
  end
end
