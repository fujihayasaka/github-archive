# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class TrackedIssues < Resolvers::Base
      type Connections.define(Objects::Issue), null: false

      def resolve(**arguments)
        object.async_repository.then do |repo|
          next ArrayWrapper.new([]) unless repo.extract_checklists_enabled?

          readable_tracked_issues(object)
        end
      end

      def readable_tracked_issues(object)
        if context[:permission].typed_can_access?("Issue", object)
          object.async_source_issue_links.then do |issue_links|
            tracked_issues_ids = issue_links.sort.pluck(:target_issue_id).compact

            if object.remote_tracking_blocks
              # Collect all the unique item IDs for issues within each tracking block
              # while filtering out duplicates and draft issues (id == 0)
              tracked_issues_ids += object.remote_tracking_blocks.map do |block|
                block&.issues&.map { |issue| issue&.key&.itemId }
              end.flatten.compact.filter { |id| id != 0 }
            end

            Platform::Loaders::ActiveRecord.load_all(::Issue, tracked_issues_ids.uniq).then do |tracked_issues|
              authorized_tracked_issues = context[:cap_filter].authorized_resources(tracked_issues.compact)
              async_tracked_issues = authorized_tracked_issues.compact.map do |tracked_issue|
                tracked_issue.async_visible_and_readable_by?(context[:viewer]).then do |readable|
                  tracked_issue if readable
                end
              end
              Promise.all(async_tracked_issues).then do |tracked_issues|
                ArrayWrapper.new(tracked_issues.compact)
              end
            end
          end
        else
          ArrayWrapper.new([])
        end
      end
    end
  end
end
