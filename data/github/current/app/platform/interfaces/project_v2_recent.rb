# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module ProjectV2Recent
      include Platform::Interfaces::Base

      description "Recent projects for the owner."

      visibility :public, environments: [:dotcom, :enterprise]

      field :recent_projects, Connections.define(Objects::ProjectV2),
        description: "Recent projects that this user has modified in the context of the owner.",
        null: false,
        connection: true

      def recent_projects
        async_owner = if @object.is_a?(::Repository)
          @object.async_owner.then { |owner| owner }
        else
          Promise.resolve(@object)
        end

        async_owner.then do |owner|
          suggester = ProjectSuggester.new(
            viewer: @context[:viewer],
            context: owner,
            load_memex_projects: true,
            load_classic_projects: false
          )
          suggester.async_recent_memex_projects
            .then { |memexes| ArrayWrapper.new(memexes) }
        end
      end
    end
  end
end
