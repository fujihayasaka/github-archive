# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class TrackedInIssues < Resolvers::Base
      type Connections.define(Objects::Issue), null: false

      def resolve(**arguments)
        object.async_repository.then do |repo|
          next ArrayWrapper.new([]) unless repo.extract_checklists_enabled?

          readable_tracked_issues_parents(object)
        end
      end

      def readable_tracked_issues_parents(object)
        if context[:permission].typed_can_access?("Issue", object)
          object.async_target_issue_links.then do |issue_links|
            parent_ids = issue_links.sort.pluck(:source_issue_id).compact

            if object.hierarchy_tracked_by
              parent_ids += object.hierarchy_tracked_by.map { |issue| issue[:item_id] }
            end

            Platform::Loaders::ActiveRecord.load_all(::Issue, parent_ids.uniq).then do |parents|
              authorized_parents = context[:cap_filter].authorized_resources(parents.compact)
              async_parents = authorized_parents.map do |parent|
                parent.async_visible_and_readable_by?(context[:viewer]).then do |readable|
                  parent if readable
                end
              end
              Promise.all(async_parents).then do |parents|
                ArrayWrapper.new(parents.compact)
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
