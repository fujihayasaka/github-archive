# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class TrackedItems < Resolvers::Base
      type Connections.define(Unions::TrackableItem), null: false

      def resolve(**arguments)
        issue_ids = object&.items.filter_map { |i| i.issue_id if i.issue_id != 0 }.compact.uniq

        Platform::Loaders::ActiveRecord.load_all(::Issue, issue_ids).then do |tracked_issues|
          authorized_tracked_issues = context[:cap_filter].authorized_resources(tracked_issues.compact)
          async_tracked_issues = authorized_tracked_issues.compact.map do |tracked_issue|
            tracked_issue.async_readable_by?(context[:viewer]).then do |readable|
              tracked_issue if readable
            end
          end

          Promise.all(async_tracked_issues).then do |tracked_issues|
            compact_issues = tracked_issues.compact
            all_items = object&.items.map do |item|
              if item&.issue_id == 0
                next ::TrackingBlocks::DraftIssue.new(
                  draft_issue: item.title,
                  owner_id: item.owner_id,
                  uuid: item.uuid,
                  closed: item.closed?,
                  position: item.position,
                  parent_issue: item.parent_issue
                )
              end
              issue_item = compact_issues.find { |i| i.id == item.issue_id }

              next nil unless issue_item

              next ::TasklistBlocks::IssueReference.new(
                issue: issue_item,
                uuid: item.uuid,
                position: item.position,
                completion: item.completion,
                parent_issue: item.parent_issue
              )
            end

            ArrayWrapper.new(all_items.compact)
          end
        end
      end
    end
  end
end
