# typed: true
# frozen_string_literal: true

# Tracks a bulk import of Issue data.
class IssueImport < ApplicationRecord::Domain::IssuesPullRequests
  include ::Repositories::BelongsToRepository
  belongs_to_repository_via_domain
  belongs_to :importer, class_name: "User"
  before_save :store_issue_ids # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  # NOTE: renaming raw_data column to issue_ids will allow the removal
  # of the aliase_attribute
  serialize :raw_data, type: Array
  alias_attribute :issue_ids, :raw_data

  # Public: Declares that the given Issue was imported by this Import job.
  #
  # issue - An Issue.
  #
  # Returns nothing.
  def importing(issue)
    imported_issue_ids << issue.id.to_s
  end

  # Public: Checks to see if the Issue was imported by this Import job.
  #
  # issue - An Issue.
  #
  # Returns true or false.
  def imported?(issue)
    imported_issue_ids.include? issue.id.to_s
  end

  # Loads the Issue IDs as a Set to ensure uniqueness and speed up checks.
  #
  # Returns a Set of String Issue IDs.
  def imported_issue_ids
    @imported_issue_ids ||= Set.new(issue_ids)
  end

  # Dumps the Set to the serialized array before saving.
  #
  # Returns nothing.
  def store_issue_ids
    self.issue_ids = imported_issue_ids.to_a
  end
end
