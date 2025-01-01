# typed: true
# frozen_string_literal: true

class DeleteDependentAbilitiesJob < ApplicationJob
  queue_as :delete_dependent_abilities

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  def perform(ids)
    with_write { Ability.delete_dependent_abilities_for!(ids) }
  end
end
