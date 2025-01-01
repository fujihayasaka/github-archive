# typed: true
# frozen_string_literal: true

module CommandPalette
  module Results
    class ProjectResult < Result
      def self.type
        Project
      end

      def self.create(project, priority, context, group = nil)
        path, subtitle = if project.owner.is_a?(Repository)
          repository = project.owner
          [
            repo_project_path(number: project.number, repository: repository, user_id: repository.owner.name),
            "in #{repository.nwo}"
          ]
        elsif project.owner.is_a?(Organization)
          [
            show_org_memex_path(memex_number: project.number, org: project.owner.name),
            "in #{project.owner.name}"
          ]
        else
          [
            show_user_memex_path(memex_number: project.number, user_id: project.owner.name),
            "in #{project.owner.name}"
          ]
        end

        args = {
          priority: priority,
          title: "#{project.name} ##{project.number}",
          typeahead: project.name,
          icon: Icons::Octicon.new(name: "project"),
          action: Actions::JumpToAction.new(path: path),
          group: group || :projects,
          object: project
        }

        # Unless the scope is the same as the project owner, add a subtitle
        if project.owner != context.scope.object
          args[:subtitle] = subtitle
        end

        new(**args)
      end
    end
  end
end
