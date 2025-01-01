# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    module MergeConditions
      class PullRequestMergeConflictStateCondition < Platform::Objects::Base
        description "Merge conflict state"

        class << self
          delegate :async_api_can_access?, to: Platform::Interfaces::PullRequestMergeCondition
          delegate :async_viewer_can_see?, to: Platform::Interfaces::PullRequestMergeCondition
        end

        implements Interfaces::PullRequestMergeCondition

        field :conflicts, [String], null: false, description: "List of conflicted files"

        def conflicts
          Platform::Loaders::ActiveRecord.load(::PullRequestConflict, object.pull_request.id, column: :pull_request_id, case_sensitive: false).then do |conflicts|
            ArrayWrapper.new([conflicts&.filenames].flatten.compact)
          end
        end

        field :is_conflict_resolvable_in_web, Boolean, description: "Is the merge conflict web resolvable", null: false

        def is_conflict_resolvable_in_web
          pr = object.pull_request
          Platform::Loaders::ActiveRecordAssociation.load(pr, :conflict).then do
            pr.conflict_resolvable?
          end
        end
      end
    end
  end
end
