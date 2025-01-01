# typed: true
# frozen_string_literal: true

module CommandPalette
  module Results
    class DiscussionResult < Result
      def self.type
        Discussion
      end

      def self.create(discussion, priority, context, group = nil)
        args = {
          priority: priority,
          title: "#{discussion.title} ##{discussion.number}",
          typeahead: discussion.title,
          icon: Icons::Octicon.for_discussion(discussion),
          action: Actions::JumpToAction.new(path: path_for_discussion(discussion)),
          group: group || :references,
          object: discussion,
        }

        if !context.scope.repository? || context.scope.repository.id != discussion.repository_id
          args[:subtitle] = "in #{discussion.repository.nwo}"
        end

        if context.subject == discussion
          args[:scope] = ResultScope.new(discussion)
        end

        new(**args)
      end

      def self.path_for_discussion(discussion)
        repository = discussion.repository
        owner = repository.owner
        number = discussion.number

        discussion_path(owner, repository, number)
      end
    end
  end
end
