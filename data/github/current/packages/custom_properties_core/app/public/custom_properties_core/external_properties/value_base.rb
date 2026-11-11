# typed: false # rubocop:disable Sorbet/StrictSigil
# frozen_string_literal: true

# Sorbet does not handle ActiveSupport::Concern well, so we need to disable strictness here

# This is a base class for external property values. External properties are an extension to the core
# custom properties functionality. They allow third-party providers to flow their existing metadata
# into our system. External property values are always strings.
module CustomPropertiesCore
  module ExternalProperties
    module ValueBase
      extend ActiveSupport::Concern
      extend T::Helpers
      include Instrumentation::Model

      abstract!

      sig { abstract.returns(String) }
      def value; end

      sig { abstract.returns(ValueBase) }
      def destroy!; end

      included do
        belongs_to :definition, class_name: self.definition_class_name, foreign_key: :definition_id, inverse_of: :external_property_values
        belongs_to :target, class_name: self.target_class_name

        # Gets the property values for a given target entity
        #
        # target - the target to get the values for
        scope :for_target, ->(target) { where(target_id: target.properties_target_id) }

        # Gets the property values for the given target ids
        #
        # target_ids - the target ids to get the values for
        scope :for_target_ids, ->(target_ids) { where(target_id: target_ids) }

        # Gets the property values for the given external property definition ids
        #
        # definition_ids - the definition ids to get the values for
        scope :for_definition_ids, ->(definition_ids) { where(definition_id: definition_ids) }

        # Gets the property value models matching the specified array of string values
        #
        # value_strings - the string values to find matching property values for
        scope :for_matching_value_strings, ->(value_strings) { where(value: value_strings) }

        # Selects property values matching provided search term.
        # Search is case insensitive and is based on `include` condition.
        #
        # search_term - the property value to search for
        scope :with_property_value_like, ->(search_term) { where("value LIKE ?", "%#{search_term}%") }

        validates_presence_of :definition_id
        validates_presence_of :target_id

        after_create_commit :instrument_create
        after_destroy_commit :instrument_destroy
        after_update_commit :instrument_update, if: :saved_changes?

        # Batch method for efficiently loading property names to avoid N+1 queries
        # When called against a single instance it returns the property name for that value object
        # When called in batch it will load all property names for the given values
        batch_method(:property_name) do |values|
          GitHub::PrefillAssociations.prefill_associations(values, :definition)

          # Return a hash mapping each value to its property name
          values.to_h do |value|
            property_name = value.definition&.property_name || ""
            [value, property_name]
          end
        end

        # Domain model classes should implement `event_payload_extension` to enhance the instrumentation event payload
        # with domain-specific fields.
        # By default, only definition_id, property_name, and value are included.
        #
        # @see #event_payload
        def self.get_event_payload_extension(target)
          respond_to?(:event_payload_extension) ? self.event_payload_extension(target) : {}
        end
      end

      private

      sig { void }
      def instrument_create
        instrument :create
      end

      sig { void }
      def instrument_destroy
        instrument :destroy
      end

      sig { void }
      def instrument_update
        instrument :update, changes_payload if changes_payload
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def event_payload
        {
          definition_id: definition_id,
          property_name: property_name,
          value: value,
        }.merge(self.class.get_event_payload_extension(target))
      end

      sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def changes_payload
        {
          old_value: previous_changes["value"]&.first,
        } if previous_changes["value"]&.first
      end
    end
  end
end
