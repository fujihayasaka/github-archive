# Public: Delegates Relay slicing and pagination to a wrapped object.
#
# Some objects (e.g. query class instances) are a bit different from Array
# and ActiveRecord::Relation instances in that they need to implement limits,
# cursor offsets and pagination internally for efficiency or correctness.
#
# For example, consider a query class that returns an Array.
#
#     class LicenseQuery
#       def results
#         Package.all.map { |package| License.new(package.license) }
#       end
#     end
#
#     resolve ->(obj, args, ctx) {
#       LicenseQuery.new.results
#     }
#
# The GraphQL Relay::ArrayConnection will pare down results by applying
# `results[cursor..-1].first(n)`. But this query is grossly inefficient
# because it pulls all Package records into memory. Instead, the query should
# accept a `limit` parameter.
#
#     class LicenseQuery
#       def initialize(limit)
#         @limit = limit
#       end
#
#       def results
#         Package.limit(@limit).map { |package| License.new(package.license) }
#       end
#     end
#
#     resolve ->(obj, args, ctx) {
#       LicenseQuery.new(limit: args[:first]).results
#     }
#
# The GraphQL Relay::ArrayConnection will still attempt to pare down results,
# yielding an empty array. The `QueryObject` connection wrapper delegates *all*
# results limiting and cursor offsetting to the query class.
#
#     class LicenseQuery
#       def first(n)
#         @limit = n
#         self
#       end
#
#       def after(cursor)
#         @cursor = cursor
#         self
#       end
#
#       def results
#         Package
#           .where("id > ?", @cursor.to_i)
#           .limit(@limit)
#           .map { |package| License.new(package.license) }
#       end
#     end
#
#     GraphQL::Relay::BaseConnection.register_connection_implementation(
#       Queries::LicenseQuery,
#       API::ConnectionWrappers::Delegator)
#
#     resolve ->(obj, args, ctx) {
#       LicenseQuery.new
#     }
#
# The target class must implement:
#
#   - #first(n) - limit results to `n` items
#   - #after(cursor) - limit results to items with an ID greater than `cursor`
#   - #has_next? - Are there results after the current result set?
#   - #has_previous? - Are there results before the current result set?
#   - #each - iterate over results
#   - #map - map over results
#
module API
  module ConnectionWrappers
    class Delegator < GraphQL::Relay::BaseConnection
      alias :target :nodes

      def cursor_from_node(node)
        encode(node.id.to_s)
      end

      def paged_nodes_array
        @paged_nodes_array ||= paged_nodes.to_a
      end

      def paged_nodes
        return @paged_nodes if defined? @paged_nodes

        items = sliced_nodes
        items = items.first(first) if first
        items = items.last(last) if last

        @paged_nodes = items
      end

      def sliced_nodes
        return @sliced_nodes if defined? @sliced_nodes

        items = nodes
        items = nodes.after(offset_from_cursor(after)) if after
        items = nodes.before(offset_from_cursor(before)) if before

        @sliced_nodes = items
      end

      def has_next_page
        target.has_next?
      end

      def has_previous_page
        target.has_previous?
      end

      def offset_from_cursor(cursor)
        decode(cursor).to_i
      end
    end
  end
end
