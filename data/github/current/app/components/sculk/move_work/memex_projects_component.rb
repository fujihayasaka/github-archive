# typed: true
# frozen_string_literal: true

module Sculk
  module MoveWork
    class MemexProjectsComponent < ResourcesComponent
      def load_more_url
        helpers.move_work_memex_projects_path(actor, total_resources: total_resources, loaded_resources: offset)
      end

      def resource_label
        :memex_project
      end

      def resources_relation
        actor.memex_projects
      end
    end
  end
end
