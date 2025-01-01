# typed: true
# frozen_string_literal: true

module Sculk
  module MoveWork
    class ProjectsComponent < ResourcesComponent
      def load_more_url
        helpers.move_work_projects_path(actor, total_resources: total_resources, loaded_resources: offset)
      end

      def resource_label
        :project
      end

      def resources_relation
        actor.projects
      end
    end
  end
end
