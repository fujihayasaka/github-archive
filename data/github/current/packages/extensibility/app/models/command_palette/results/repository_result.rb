# typed: true
# frozen_string_literal: true

module CommandPalette
  module Results
    class RepositoryResult < Result
      def self.type
        Repository
      end

      def self.create(repo, priority, context, group = nil)
        args = {
          priority: priority,
          title: repo.name_with_display_owner,
          scope: ResultScope.new(repo),
          icon: Icons::Octicon.for(repo),
          action: Actions::JumpToAction.new(path: repository_path(repo.owner, repo)),
          group: group || :repositories,
          object: repo
        }

        if context.scope.owner == repo.owner
          args[:typeahead] = repo.name
          args[:match_fields] = [repo.name, "/#{repo.name}"]
        end

        new(**args)
      end
    end
  end
end
