# typed: true
# frozen_string_literal: true

class Hook::Payload
  # Public: Instantiates the correct Hook::Payload model for the given Hook::Event.
  #
  # hook_event - The Hook::Event model to build a payload for.
  #
  # Returns an instance of a Hook::Payload model.
  # Raises NameError if the Hook::Payload model is not found.
  def self.for_event(hook_event)
    klass = "Hook::Payload::#{hook_event.event_type.camelize}Payload".constantize
    klass.new hook_event
  end

  attr_reader :hook_event

  def initialize(hook_event)
    @hook_event = hook_event
  end

  def to_payload_hash
    raise NotImplementedError, "#{self.class} must implement #to_payload_hash"
  end

  # Public: Evaluates the payload instance.
  # Caches the result to avoid doingduplicate work.
  #
  # Returns a Hash.
  def to_hash
    @to_hash ||= begin
      event_type = @hook_event.event_type
      tags = GitHub::TaggingHelper.create_hook_event_tags(event_type, @hook_event.try(:action))

      GitHub.dogstats.distribution_time("hooks.payload.apply", tags: tags) do
        record_query_counts("payload.queries") do
          payload = self.to_payload_hash # domain-isolation-query-violation:ignore:packages/issues (SELECT)
          # Specify default payload values. These
          # will be appended to the payload for the specific event.
          # Values specified in the payload take precedence over
          # these default values.
          payload[:repository] ||= api_serialize(:repository_with_custom_properties_hash, hook_event.target_repository) if hook_event.target_repository
          payload[:organization] ||= api_serialize(:organization_hash, hook_event.target_organization) if hook_event.target_organization
          payload[:enterprise] ||= api_serialize(:business_hash, hook_event.target_business) if hook_event.target_business
          payload[:sender] ||= api_serialize(:user_hash, hook_event.actor) if hook_event.actor
          payload.freeze
          payload
        end
      end
    end
  rescue StandardError => e # rubocop:todo Lint/GenericRescue
    tags << "exception_class:#{T.must(e.class.name).underscore}"
    GitHub.dogstats.increment("hooks.payload_hydration.error", tags: tags)
    raise e
  end

  def changes_payload
    return {} unless hook_event.changes

    {
      changes: hook_event.changes,
    }
  end

  private

  # This call-through serves as a single point of entry to `Api::Serializer`.
  # The plan is to add an `api_version:` option to `options`,
  # so that the serializers can switch on the `Hook`'s pinned API version.
  # @see https://github.com/github/github/pull/177724 for a spike.
  def api_serialize(serialize_method, object, options = {})
    Api::Serializer.serialize(serialize_method, object, { serialize_login: :display }.merge(options)) # rubocop:disable GitHub/ApiSerializeInHookPayloads
  end

  def record_query_counts(metric)
    if GitHub.flipper[:webhooks_payload_query_counts].enabled?
      @hook_event.record_query_counts(metric, true) do
        yield
      end
    else
      yield
    end
  end
end
