# typed: strict
# frozen_string_literal: true

class HydroStratocasterRepositoryRefUpdateRecordedJob < HydroMessageJob
  include GitHub::Memoizer

  queue_as :hydro_stratocaster_repository_ref_update_recorded

  retry_on_dirty_exit

  sig { void }
  def perform
    if not_created_or_deleted?
      GitHub.stratocaster.queue(Stratocaster::Event::PUSH_EVENT, message[:push_id], message[:repository_id], message[:actor_id])
    end
  end

  private

  sig { returns(T::Boolean) }
  def not_created_or_deleted?
    message[:before] != GitHub::NULL_OID && message[:after] != GitHub::NULL_OID
  end
end
