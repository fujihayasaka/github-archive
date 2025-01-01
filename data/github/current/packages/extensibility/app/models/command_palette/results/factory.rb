# typed: true
# frozen_string_literal: true

module CommandPalette
  module Results
    class Factory
      RESULT_TYPES = [
        DiscussionResult,
        IssueResult,
        PullRequestResult,
        MemexProjectResult,
        OrganizationResult,
        ProjectResult,
        RepositoryResult,
        TeamResult,
        UserResult,
      ].to_h { |result_class| [result_class.type, result_class] }

      # Factory method
      def self.build(object, priority, context, group = nil)
        RESULT_TYPES[object.class]&.create(object, priority, context, group)
      end
    end
  end
end
