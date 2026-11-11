# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class ClearAbilitiesJob < ApplicationJob
  exempt_from_tenant_context_requirement

  queue_as :clear_abilities

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  def self.allow_async_enqueues?
    false
  end

  # Perform a deletion of abilities referencing any of the
  # specified abilities through the indirect grant ancestry information in
  # parent_id and/or grandparent_id
  #
  # ids - IDs of the abilities whose dependent abilities we want to delete.
  #
  def perform(ability_id, ability_type)
    with_write { Ability.clear!(ability_id, ability_type) }
  end
end
