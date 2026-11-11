# typed: strict
# frozen_string_literal: true

# Hydro event subscriptions related to membership updates to orgs, teams and repos.
Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe(/(org|team|repo).(add|remove)_member\z/) do |payload|
    object = payload[:team] || payload[:repo] || payload[:org]

    if object
      action = if payload[:action]
        payload[:action].upcase.to_sym
      end

      context = object.class.hydro_context
      group_id = object.id

      message = {
        request_context: serializer.request_context(GitHub.context.to_hash),
        context: context || :CONTEXT_UNKNOWN,
        actor: serializer.user(payload[:actor]),
        user: serializer.user(payload[:user]),
        action: action || :ACTION_UNKNOWN,
        group_id: group_id,
        reason: serializer.enum(
          type: Hydro::Schemas::Github::V1::MembershipUpdate::Reason,
          value: payload[:reason],
          default: :REASON_UNKNOWN
        ),
        customer_id: Licensing::Customer.id_for(object),
      }

      if FeatureFlag.vexi.enabled?(:membership_update_partition_key, object, default: false)
        # Partition by the affected user so all membership updates for a given
        # user are routed to the same partition and therefore consumed in order.
        # Without a partition key Kafka assigns partitions round-robin, which let
        # two events for the same user land on different partitions/pods and be
        # processed out of order.
        publish(message,
          partition_key: payload[:user]&.id,
          schema: "github.v1.MembershipUpdate",
          topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }, # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
        )
      else
        publish(message, schema: "github.v1.MembershipUpdate", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
      end
    end
  end
end
