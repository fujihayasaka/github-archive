# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class Base < GraphQL::Schema::Object
      # Extend field execution to make sure that pagination arguments
      # are present and within our bounds
      class CheckPaginationExtension < GraphQL::Schema::FieldExtension
        # Add metadata to check for pagination-related selections
        def apply
          if field.extras.include?(:ast_node)
            @delete_ast_node = false
          else
            field.extras([:ast_node])
            @delete_ast_node = true
          end
        end

        def resolve(arguments:, object:, **_rest)
          args = arguments
          ast_node = args[:ast_node]

          if @delete_ast_node
            args = args.reject { |k| k == :ast_node }
          end

          check_pagination_arguments!(args, ast_node)
          yield(object, args)
        end

        private

        def check_pagination_arguments!(args, ast_node)
          first = args[:first]
          last = args[:last]
          numeric_page = args[:numeric_page]

          if first.nil? && last.nil? && using_fields_on_connection?(ast_node)
            raise Platform::Errors::MissingPaginationBoundaries.new(field)
          elsif numeric_page.present? && !Platform::GlobalScope.origin_rest_api?
            raise Platform::Errors::InvalidNumericPageOrigin.new(field, "numericPage", Platform::GlobalScope.origin)
          elsif first.present? && first < 0
            raise Platform::Errors::InvalidPagination.new(field, "first")
          elsif last.present? && last < 0
            raise Platform::Errors::InvalidPagination.new(field, "last")
          end
        end

        def using_fields_on_connection?(ast_node)
          begin
            ast_node.selections.any? { |sel| (sel.name == "pageInfo" || sel.name == "edges" || sel.name == "nodes") }
          rescue NoMethodError
            raise Platform::Errors::MissingPaginationBoundaries.new(field)
          end
        end
      end
    end
  end
end
