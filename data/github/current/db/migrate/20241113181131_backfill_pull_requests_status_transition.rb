# typed: true
# frozen_string_literal: true

require "github/transitions/20241113181131_backfill_pull_requests_status"

class BackfillPullRequestsStatusTransition < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::BackfillPullRequestsStatus.new(arguments)
    transition.run
  end

  def self.down
  end
end
