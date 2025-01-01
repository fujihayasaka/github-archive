# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class CalculateDiscussionTotalVotesJob < ApplicationJob
  queue_as :calculate_discussion_total_votes
  retry_on_dirty_exit

  def perform(discussion_id)
    with_write { DiscussionVote.update_votes_counts(discussion_id) }
  end
end
