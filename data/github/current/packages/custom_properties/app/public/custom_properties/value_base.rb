# typed: false # rubocop:disable Sorbet/StrictSigil
# frozen_string_literal: true

# Sorbet does not handle ActiveSupport::Concern well, so we need to disable strictness here

# In order to avoid N+1s where consumers interface with the definition through the ValueBase
# model active record queries should likely be made with`.includes(:definition)`
module CustomProperties
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
      belongs_to :definition, class_name: self.definition_class_name, foreign_key: :definition_id, inverse_of: :custom_property_values
      belongs_to :target, respond_to?(:target_scope) ? self.target_scope : nil, class_name: self.target_class_name

      # Gets the property values for a given target entity
      #
      # target - the target to get the values for
      scope :for_target, ->(target) { where(target_id: target.id) }

      # Gets the property values for the given target ids
      #
      # target_ids - the target ids to get the values for
      scope :for_target_ids, ->(target_ids) { where(target_id: target_ids) }

      # Gets the property values for a given custom property definition
      #
      # definition - the definition to get the values for
      scope :for_definition, ->(definition) { where(definition_id: definition.id) }

      # Gets the property values for the given custom property definition ids
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

      after_create_commit :instrument_create # rubocop:todo GitHub/AvoidActiveRecordCallbacks
      after_destroy_commit :instrument_destroy # rubocop:todo GitHub/AvoidActiveRecordCallbacks
      after_update_commit :instrument_update, if: :saved_changes? # rubocop:todo GitHub/AvoidActiveRecordCallbacks

      # Domain model classes should implement `event_payload_extension` to enhance the instrumentation event payload
      # with domain-specific fields.
      # By default, only definition_id, property_name, and value are included.
      #
      # @see #event_payload
      def self.get_event_payload_extension(target)
        respond_to?(:event_payload_extension) ? self.event_payload_extension(target) : {}
      end

      # Domain model class might implement `event_prefix` to customize the event prefix.
      # It is used to instrument updates of target property values.
      # Resulting event name will be `{event_prefix}.update_custom_property_values`.
      # Defaults to the underscored target class name.
      #
      # @see CustomPropertiesManager#set_properties_for
      def self.get_event_prefix
        respond_to?(:event_prefix) ? self.event_prefix : "#{self.target_class_name.underscore}"
      end
    end

    sig { returns(String) }
    def property_name
      definition&.property_name || ""
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
