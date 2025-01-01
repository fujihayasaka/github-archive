# typed: true
#frozen_string_literal: true

module Platform
  module Loaders
    class DirectProjectUserAbilities < Platform::Loader
      def self.load(project:, user:)
        self.for(project).load(user.id)
      end

      def initialize(project)
        @project = project
      end

      # Internal: Fetch the direct user abilities on the given projects.
      #
      # Returns a Hash{user id => Ability}.
      def fetch(user_ids)
        ::Ability.where(
          actor_type: "User",
          actor_id: user_ids,
          subject_type: "Project",
          subject_id: @project.id,
          priority: ::Ability.priorities[:direct],
        ).index_by(&:actor_id)
      end
    end
  end
end
