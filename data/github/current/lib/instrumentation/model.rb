# typed: true
# frozen_string_literal: true

require "active_support/core_ext/string/inflections"
require "context"
require "audit"
require "instrumentation"

module Instrumentation
  # A module of helper methods so classes can instrument themselves.
  module Model
    extend T::Helpers
    include Kernel

    module ClassMethods
      extend T::Helpers
      requires_ancestor { Module }

      # Internal: provide a default event_prefix that matches
      # nicely to the class name.  The default instance level `event_prefix`
      # uses this.
      def default_event_prefix
        @default_event_prefix ||= T.must(name).underscore.to_sym
      end
    end

    class IdentifierError < ArgumentError; end

    mixes_in_class_methods(ClassMethods)

    # Public: Instruments events for this object.
    #
    # key     - String suffix of the event key.  See #event_prefix.
    # payload - Hash of additional payload information. See #event_payload.
    # &block  - Optional Block for timing operations.
    #           See ActiveSupport::Notifications.instrument.
    #
    # Returns nothing.
    def instrument(key, payload = {}, &block)
      if Instrumentation.suppressed?
        yield payload if block_given?
        return
      end

      prefix = payload.delete(:prefix) || event_prefix

      combined_payload = event_payload.merge(payload)

      verify_identifying_fields("#{prefix}.#{key}", combined_payload)

      expanded_payload = Context::Expander.expand(combined_payload)

      GitHub.dogstats.increment("model_event_triggered.#{prefix}.count", tags: ["action:#{prefix}.#{key}"])
      instrumentation_service.instrument "#{prefix}.#{key}", expanded_payload, &block
    end

    # Public: Returns the payload for an instrumentation event for this object.
    #
    # key     - String suffix of the event key.  See #event_prefix.
    # payload - Hash of additional payload information. See #event_payload.
    #
    # Returns Array.
    def instrumentation_payload(key, payload = {})
      if Instrumentation.suppressed?
        return
      end

      prefix = payload.delete(:prefix) || event_prefix

      combined_payload = event_payload.merge(payload)

      verify_identifying_fields("#{prefix}.#{key}", combined_payload)

      ["#{prefix}.#{key}", Context::Expander.expand(combined_payload)]
    end

    # Internal: Defines the event key prefix for all model events.
    #
    # Defaults to :my_model if the class this thing is included in is MyModel.
    # Feel free to override to provide a more semantic, meaningful name
    # if you so desire.
    #
    # Returns a String.
    def event_prefix
      T.cast(self.class, ClassMethods).default_event_prefix
    end

    # Internal: Defines the default payload for every event.
    #
    # Returns a Hash.
    def event_payload
      {}
    end

    # Internal: Defines the payload to describe the current subject.
    # Can be overridden in model to change fields returned.
    #
    # prefix - Key prefix that can be set to override Hash prefix.
    #
    # Example
    #
    #   event_context                 # => { :user_id => 1 }
    #   event_context(prefix: :actor) # => { :actor_id => 1 }
    #
    # Returns a Hash.
    def event_context(prefix: event_prefix)
      return {} unless respond_to? :id
      {
        "#{prefix}_id".to_sym => T.unsafe(self).id,
      }
    end

    # Internal: Defines the instrumentation service instance.
    #
    # Returns an ActiveSupport::Notifications::Service or compatible object.
    def instrumentation_service
      @instrumentation_service ||= GitHub.instrumentation_service
    end
    attr_writer :instrumentation_service

    # Internal: Defines the instrumentation service instance.
    #
    # Returns an ActiveSupport::Notifications::Service or compatible object.
    def raise_on_verify?
      return @raise_on_verify if defined?(@raise_on_verify)
      @raise_on_verify = GitHub.audit_log_raise_on_verify?
    end
    attr_writer :raise_on_verify

    private

    def verify_identifying_fields(key, payload)
      return unless is_audit_action?(key)
      return if GitHub.single_business_environment?

      identifiers = payload.symbolize_keys.slice(:user, :user_id, :org, :org_id, :business, :business_id, :actor, :actor_id)

      checks = [
        {
          object_field: :user,
          object_id_field: :user_id,
          acceptable_types: [::User, String, ::Bot, ::Organization, ::Mannequin, ::ProgrammaticAccessBot],
        },
        {
          object_field: :actor,
          object_id_field: :actor_id,
          acceptable_types: [::User, String, ::Bot, ::Organization, ::Mannequin, ::ProgrammaticAccessBot],
        },
        {
          object_field: :org,
          object_id_field: :org_id,
          acceptable_types: [::Organization, String],
        },
        {
          object_field: :business,
          object_id_field: :business_id,
          acceptable_types: [::Business, String],
        },
      ]

      checks.each do |check|
        field = check[:object_field]
        id_field = check[:object_id_field]
        types = check[:acceptable_types]

        if identifiers.key?(field)
          id = identifiers[id_field]
          obj = identifiers[field]

          type_mismatch = obj.present? &&
          if obj.is_a?(Array)
            obj.any? { |o| !types.include?(o.class) }
          else
            !types.include?(obj.class)
          end
          id_mismatch = obj.respond_to?(:id) && identifiers.has_key?(id_field) && obj.id != id

          # The object should be only of the types allowed in acceptable_types
          if type_mismatch
            GitHub::Logger.log({
              log_message: "[Audit Log] Object type mismatch",
              action: key,
              field: field,
              acceptable_types: types,
              object_class: obj.class.to_s
            })

            GitHub.dogstats.increment("audit.service.type_mismatch", tags: ["type:#{field}", "action:#{key}", "got_type:#{obj.class}"])

            err = IdentifierError.new("#{field}, on action #{key}, is not a #{types.join(",")}, but is a #{obj.class}")

            Failbot.report(err, { action: key })

            raise err if raise_on_verify?

            payload[:data] ||= {}
            payload[:data][:_invalid] = true
          end

          # if there is an object, and an id for that object, we should check if they match
          if id_mismatch
            GitHub::Logger.log({
              log_message: "[Audit Log] Object id mismatch",
              action: key,
              field: field,
              id_field: id_field,
              id: id,
              object_id: obj.id,
              object_class: obj.class.to_s
            })

            GitHub.dogstats.increment("audit.service.id_mismatch", tags: ["type:#{field}", "action:#{key}"])

            err = IdentifierError.new("#{id_field} does not match obj.id, #{id_field}: #{id}, obj.id: #{obj.id}")

            Failbot.report(err, { action: key })

            raise err if raise_on_verify?

            payload[:data] ||= {}
            payload[:data][:_invalid] = true
          end
        # If there is no object, but there is an id field
        elsif identifiers.key?(id_field)
          GitHub::Logger.log({
            log_message: "[Audit Log] Object missing",
            action: key,
            field: field,
            id_field: id_field,
            id: id,
          })
          GitHub.dogstats.increment("audit.service.missing_object", tags: ["type:#{field}", "action:#{key}"])
        end

      end
    end

    def is_audit_action?(key)
      ::Audit::ALL_ACTIONS.include?(key.to_s)
    end
  end
end
