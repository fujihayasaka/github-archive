# typed: strict
# frozen_string_literal: true

# In order to avoid N+1s where consumers interface with the definition through the `CustomPropertyValue`
# model or `CustomProperties::IPropertyValue` interface, active record queries should likely be made with
# `CustomPropertyValue.includes(:definition)`
#
# If the implementation queries `CustomPropertyDefinition`s prior to querying associated `CustomPropertyValue`s from
# the database, then the `ValueWithDefinition` wrapper class, which also implements
# `CustomProperties::IPropertyValue` can be used to construct pairs of `CustomPropertyDefinition` and
# `CustomPropertyValue` objects to avoid round trips to the database.
class CustomPropertyValue < ApplicationRecord::Domain::Repositories
  extend T::Sig
  include Instrumentation::Model

  belongs_to :definition, class_name: "CustomPropertyDefinition", foreign_key: :definition_id, inverse_of: :custom_property_values
  belongs_to :target, -> { where(active: true) }, class_name: "Repository"

  # Public: gets the values for active repos, filtering out soft-deleted and hard-deleted ones
  scope :for_active_repos, -> { joins(:target) }

  # Public: gets the property values for a given target entity
  #
  # target - the target to get the values for
  scope :for_target, ->(target) { where(target_id: target.id, target_type: target.class.name) }

  after_create_commit :instrument_create # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_destroy_commit :instrument_destroy # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_update_commit :instrument_update, if: :saved_changes? # rubocop:todo GitHub/AvoidActiveRecordCallbacks

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
      repo: target,
      definition_id: definition_id,
      property_name: property_name,
      value: value,
      org: target&.owner,
    }
  end

  sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def changes_payload
    {
      old_value: previous_changes["value"]&.first,
    } if previous_changes["value"]&.first
  end
end
