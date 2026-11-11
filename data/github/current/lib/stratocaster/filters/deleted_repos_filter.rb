# typed: true
# frozen_string_literal: true

module Stratocaster::Filters
  class DeletedReposFilter < BaseFilter
    # Filters a list of events to exclude events where the target repository has been deleted
    #
    # events - Array of Stratocaster::Event items to filter in place.
    #
    # Returns an array of Stratocaster::Event items
    def self.apply(events, viewer)
      events.delete_if { |event| !event.user_event? && (event.repo_record.blank? || event.repo_record.deleted?) }

      fork_ids = events.select(&:fork_event?).map(&:forkee_id)
      existing_fork_ids = Repository.where(id: fork_ids).pluck(:id)

      events.delete_if do |event|
        event.fork_event? && !existing_fork_ids.include?(event.forkee_id)
      end
    end
  end
end
