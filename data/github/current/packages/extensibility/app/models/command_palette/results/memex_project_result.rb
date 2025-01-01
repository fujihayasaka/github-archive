# typed: true
# frozen_string_literal: true

module CommandPalette
  module Results
    class MemexProjectResult < Result
      extend T::Sig

      def self.type
        MemexProject
      end

      sig { params(memex: MemexProject, priority: Integer, context: CommandPalette::Context, group: T.untyped).returns(MemexProjectResult) }
      def self.create(memex, priority, context, group = nil)
        args = {
          priority: priority,
          title: "#{memex.name} ##{memex.number}",
          typeahead: memex.name,
          icon: Icons::Octicon.new(name: memex.is_template? ? "project-template" : "table"),
          action: Actions::JumpToAction.new(path: memex.url&.path),
          group: group || :memex_projects,
          object: memex
        }

        if context.subject == memex
          args[:scope] = ResultScope.new(memex)
        end

        # Unless the scope is the same as the project owner, add a subtitle
        if memex.owner != context.scope.owner
          args[:subtitle] = "in #{memex.owner.name}"
        end

        new(**args)
      end
    end
  end
end
