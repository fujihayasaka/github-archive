# typed: true
# frozen_string_literal: true

module Sculk
  module MoveWork
    class RepositoriesComponent < ResourcesComponent
      def repositories
        resources
      end

      def load_more_url
        helpers.move_work_repositories_path(actor, total_resources: total_resources, loaded_resources: offset, repository: selected_resource_name)
      end

      def can_transfer_ownership?(repository)
        repository.can_transfer_ownership?
      end

      def resources_relation
        actor.repositories
          .where.not(id: actor.configuration_repository&.id)
          .recently_updated
      end

      def resource_label
        :repository
      end
    end
  end
end
