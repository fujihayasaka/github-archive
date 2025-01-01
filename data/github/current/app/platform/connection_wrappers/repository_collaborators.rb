# typed: true
# frozen_string_literal: true

module Platform
  module ConnectionWrappers
    class RepositoryCollaborators < Relation
      attr_reader :collaborators_count

      def initialize(relation, arguments, field: nil, max_page_size: nil, parent: nil, context: nil, collaborators_count: nil, inverse_relation_exists: nil)
        @collaborators_count = collaborators_count
        @inverse_relation_exists = inverse_relation_exists
        super(
          relation,
          first: arguments[:first],
          last: arguments[:last],
          before: arguments[:before],
          after: arguments[:after],
          arguments: arguments,
          field: field,
          max_page_size: max_page_size,
          parent: parent,
          context: context
        )
      end

      def inverse_relation_exists?
        if @inverse_relation_exists.nil?
          super
        else
          @inverse_relation_exists
        end
      end
    end
  end
end
