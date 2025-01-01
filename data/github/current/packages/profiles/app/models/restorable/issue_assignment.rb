# typed: true
# frozen_string_literal: true

# Internal: Belongs to a Restorable and stores the issue id for an issue that
# was assigned to a user. The user association is stored on a Restorable
# scenario class like Restorable::OrganizationUser.
#
# Usage:
#
#  > user = User.find_by_login("jonmagic")
#  > restorable = Restorable.create
#  > assigned_issues = Issue.assigned_to(user).all
#  > Restorable::IssueAssignment.backup(:restorable => restorable, :issues => assigned_issues)
#  > Restorable::IssueAssignment.restore(:restorable => restorable, :user => user)
#
# This class and all of it's methods should only ever be used by other
# Restorable classes and specifically Restorable scenario classes/models like
# Restorable::OrganizationUser.
class Restorable
  class IssueAssignment < ApplicationRecord::Domain::Restorables

    # A set of common restorable type model helper methods.
    extend TypeHelpers

    belongs_to :restorable

    validates_presence_of :restorable_id, :issue_id
    validates_uniqueness_of :restorable_id, scope: :issue_id

    # Internal: Create a set of restorable_issue_assignments records.
    #
    # restorable - Restorable parent instance.
    # issues - An array of issues.
    def self.backup(restorable:, issues:)
      save_models(restorable, issues)
    end

    # Internal: Restore issue assignments for this user.
    #
    # restorable - Restorable parent instance.
    # user - User instance that must have read permissions for the issues being
    #        assigned.
    def self.restore(restorable:, user:)
      restorable.restoring(:restorable_issue_assignments)

      measure_restore_time do
        issue_ids = restorable.issue_assignments.pluck(:issue_id)

        throttle_batches(Issue.where(id: issue_ids)) do |issue|
          issue.add_assignees user
          issue.save
        end
      end

      restorable.restored(:restorable_issue_assignments)
    end

    # Internal: Bulk insert sql.
    #
    # Returns a String.
    def self.insert_ignore_sql
      <<-SQL
        INSERT IGNORE INTO
          restorable_issue_assignments
          (restorable_id,issue_id)
        :values
      SQL
    end

    # Internal: Create an array with needed values from models.
    #
    # restorable_id - Integer id of Restorable.
    # issues - Array of issues.
    #
    # Returns an Array of arrays.
    def self.values(restorable_id, issues)
      issues.map do |issue|
        [
          restorable_id, # restorable_id
          issue.id, # issue_id
        ]
      end
    end

    # Internal: The metric name for statsd.
    #
    # Returns a Symbol.
    def self.metric_name
      :issue_assignment
    end
  end
end
