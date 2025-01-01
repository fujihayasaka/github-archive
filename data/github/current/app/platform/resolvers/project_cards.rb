# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class ProjectCards < Resolvers::Base
      extend Platform::Objects::Base::Field::ManualConnectionArguments

      MAX_PAGE_SIZE = 100

      # Defer the loading of `ProjectCard` to work around cyclical dependency
      def self.type_expr
        Connections.define(Objects::ProjectCard)
      end

      has_connection_arguments

      argument :archived_states, [Enums::ProjectCardArchivedState, null: true],
        required: false,
        description: "A list of archived states to filter the cards by",
        default_value: [:archived, :not_archived]

      def resolve(**arguments)
        Platform::Helpers::ProjectDeprecation.ensure_api_availability(context[:viewer], context[:oauth_app], context[:user_agent]) do
          return Platform::ConnectionWrappers::ArrayWrapper.new(
            [],
            first: arguments[:first],
            last: arguments[:last],
            after: arguments[:after],
            before: arguments[:before],
            arguments: arguments,
            max_page_size: MAX_PAGE_SIZE,
            parent: object,
            context: context
          )
        end

        Platform::ConnectionWrappers::ProjectCards.new(
          Platform::Helpers::ProjectCards.new(object, arguments, context),
          first: arguments[:first],
          last: arguments[:last],
          after: arguments[:after],
          before: arguments[:before],
          arguments: arguments,
          max_page_size: MAX_PAGE_SIZE,
          parent: object,
          context: context,
        )
      end
    end
  end
end
