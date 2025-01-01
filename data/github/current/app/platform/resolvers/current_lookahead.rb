# typed: strict
# frozen_string_literal: true

module Platform
  module Resolvers
    module CurrentLookahead
      extend T::Helpers

      include GitHub::Memoizer

      requires_ancestor { GraphQL::Schema::Resolver }

      sig { returns(T.nilable(GraphQL::Execution::Lookahead)) }
      memoize def current_lookahead
        elements = context.current_path

        return nil if elements.blank?

        current_lookahead = context.query.lookahead

        elements.each do |element|
          next if element.is_a?(Numeric)

          # https://github.com/rmosolgo/graphql-ruby/blob/db7a9bcaceb77dc0af78b73e0d5c2ad849c27598/lib/graphql/execution/lookahead.rb#L174
          # When accessing GraphQL::Execution::Lookahead#selections with no arguments, it should return each selection with one ast node, based on
          # https://github.com/rmosolgo/graphql-ruby/blob/db7a9bcaceb77dc0af78b73e0d5c2ad849c27598/lib/graphql/execution/lookahead.rb#L267
          # when the field is not aliased then we will use the field name as the key
          selections = current_lookahead.selections.index_by { |selection| selection.ast_nodes.first.alias || selection.field.name }
          return nil unless selections.key?(element.to_s)

          current_lookahead = selections[element.to_s]
        end

        current_lookahead
      end

      sig do
        type_parameters(:U)
          .params(
            default: T.type_parameter(:U),
            block: T.proc.params(lookahead: GraphQL::Execution::Lookahead).returns(T.type_parameter(:U)))
          .returns(T.type_parameter(:U))
      end
      def with_safe_access_to_current_lookahead(default, &block)
        begin
          curr_lookahead = current_lookahead
          if curr_lookahead.nil?
            report_error(StandardError.new("current_lookahead is nil"))
            return default
          end
          if curr_lookahead.is_a?(GraphQL::Execution::Lookahead::NullLookahead)
            report_error(StandardError.new("current_lookahead is a NullLookahead"))
            return default
          end
          yield(curr_lookahead)
        rescue StandardError => e  # rubocop:todo Lint/RescueException
          report_error(e)
          default
        end
      end

      sig { returns(T::Boolean) }
      def with_items?
        with_safe_access_to_current_lookahead(true) do |current_lookahead|
          current_lookahead.selects?("edges") || current_lookahead.selects?("nodes")
        end
      end

      sig { returns(T::Boolean) }
      def with_total_count?
        with_safe_access_to_current_lookahead(true) do |current_lookahead|
          current_lookahead.selects?("totalCount")
        end
      end

      sig { returns(T::Boolean) }
      def with_page_info?
        with_safe_access_to_current_lookahead(true) do |current_lookahead|
          current_lookahead.selects?("pageInfo")
        end
      end

      private

      sig { params(error: StandardError).void }
      def report_error(error)
        # Using `app: "github-graceful-degradation"` because it won't break the code execution,
        # and I don't want to consume Sentry quota for this.
        Failbot.report(error, app: "github-graceful-degradation", "gh.graphql.context.current_path": context.current_path)
      end
    end
  end
end
