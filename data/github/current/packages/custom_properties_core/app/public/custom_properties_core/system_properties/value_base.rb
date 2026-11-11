# typed: false # rubocop:disable Sorbet/StrictSigil
# frozen_string_literal: true

# Sorbet does not handle ActiveSupport::Concern well, so we need to disable strictness here

# This is a base class for system property values. This is an optional extension to the core
# custom properties functionality. System property definitions are predefined and cannot be created or modified
# by users. They are used to store system-level properties for entities.
module CustomPropertiesCore
  module SystemProperties
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
        belongs_to :target, respond_to?(:target_scope) ? self.target_scope : nil, class_name: self.target_class_name
        destroy_in_background_with :target, run_if: ->(_) { FeatureFlag.vexi.enabled?(:custom_properties_system_properties_lifecycle, default: false) }

        # Gets the property values for a given target entity
        #
        # target - the target to get the values for
        scope :for_target, ->(target) { where(target_id: target.properties_target_id) }

        # Gets the property values for the given target ids
        #
        # target_ids - the target ids to get the values for
        scope :for_target_ids, ->(target_ids) { where(target_id: target_ids) }

        # Gets the property values for the given system property definition ids
        #
        # definition_ids - the definition ids to get the values for
        scope :for_definition_ids, ->(definition_ids) { where(definition_id: definition_ids) }

        # Gets the property value models matching the specified array of string values
        #
        # value_strings - the string values to find matching property values for
        scope :for_matching_value_strings, ->(value_strings) { where(value: value_strings) }

        # Selects all property values with their target entity. This scope works in conjunction with
        # the `belongs_to :target` association by applying the `target_scope` when selecting rows. Using this scope
        # means querying all rows in the values table, where targets with target_scope exist.
        #
        # This scope is used with other defined scopes to avoid large queries. Typically it is used for calculating
        # property usage counts. There is a `.count` applied to the query so it will only perform a row count
        # in the usage context.
        scope :with_target_scope, -> { joins(:target) }

        # Selects property values matching provided search term.
        # Search is case insensitive and is based on `include` condition.
        #
        # search_term - the property name to search for
        scope :with_property_value_like, ->(search_term) { where("value LIKE ?", "%#{search_term}%") }

        validates_presence_of :definition_id

        after_create_commit :instrument_create
        after_destroy_commit :instrument_destroy
        after_update_commit :instrument_update, if: :saved_changes?

        # Domain model classes should implement `event_payload_extension` to enhance the instrumentation event payload
        # with domain-specific fields.
        # By default, only property_name, and value are included.
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
          property_name: definition_id.to_s,
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
