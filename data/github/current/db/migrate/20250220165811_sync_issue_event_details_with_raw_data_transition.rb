# typed: true
# frozen_string_literal: true

require "github/transitions/20250218163651_sync_issue_event_details_with_raw_data"

class SyncIssueEventDetailsWithRawDataTransition < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::SyncIssueEventDetailsWithRawData.new(arguments)
    transition.run
  end

  def self.down
  end
end
