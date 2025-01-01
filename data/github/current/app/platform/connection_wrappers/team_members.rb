# typed: true
# frozen_string_literal: true

module Platform
  module ConnectionWrappers
    class TeamMembers < Relation
      def initialize(relation,
        parent: nil,
        field: nil,
        context: {},
        first: nil,
        after: nil,
        max_page_size: nil,
        last: nil,
        before: nil,
        edge_class: nil,
        arguments: nil
      )
        super
        scope = ::Team::Membership::ScopeBuilder.new(
          team_id: parent.id,
          viewer: context[:viewer],
          membership: arguments[:membership],
          role: arguments[:role],
          query: arguments[:query],
          pagination: pagination_options,
          max_members_limit: arguments[:max_members_limit],
        ).scope
        if (ordering = arguments[:order_by])
          if ordering[:field] == "rank"
            direction = ordering[:direction].downcase.to_sym
            scope = parent.ranked_members_for(
              context[:viewer],
              scope: scope,
              direction: direction
            )
          else
            scope = scope.order("users.#{ordering[:field]} #{ordering[:direction]}")
          end
        end
        @items, @orderings = Ordering.from_relation(scope)
      end

      def total_count
        # Use the base scope here because we shouldn't use our
        # any optimized pagination logic for counting.
        base_scope_builder.count
      end

      def record_at_offset(page, last_page, offset)
        return super unless pagination_optimizations?
        # Use a new scope here since we don't want the pagination optimizations
        # in the scope for calculating where to paginate.
        if page <= last_page
          find_user_by_id(users_scope.offset(offset)&.first&.id)
        else
          find_user_by_id(users_scope.last&.id)
        end
      end

      def find_user_by_id(id)
        return unless id
        User.find(id)
      end

      def cursor_for(async_user)
        if pagination_optimizations?
          # We know that in this case our cursors always
          # look like [user.id] and we can hardcode this.
          ::Promise.resolve(async_user).then do |user|
            encode_cursor([user.id])
          end
        else
          super
        end
      end

      # Look for items on the _other side_ of the cursor. Optimized for
      # an abilities query if it can be satisfied by it.
      def inverse_relation_exists?
        if pagination_optimizations?
          @inverse_relation_exists ||= begin
            if after
              values = decode_cursor(after)
              relation = users_scope.where("id <= ?", values.first)
            end

            if before
              values = decode_cursor(before)
              relation = users_scope.where("id >= ?", values.first)
            end

            relation.exists?
          end
        else
          super
        end
      end

      # These pagination options are passed into the scope builder if they are safe to apply.
      def pagination_options
        return {} unless pagination_optimizations?

        # Again here we know that a cursor will look like [user.id]
        # so we can work with that assumption.
        if after
          after_user_id = decode_cursor(after).first
        end

        if before
          before_user_id = decode_cursor(before).first
        end

        { first: first, last: last, before: before_user_id, after: after_user_id }
      end

      # We allow the pagination optimizations whenever there's no
      # custom order_by and no user login search query given.
      def pagination_optimizations?
        @arguments[:order_by].blank? && @arguments[:query].blank?
      end

      # Use for cases where we don't want the pagination based builder
      def base_scope_builder
        @base_scope_builder ||= ::Team::Membership::ScopeBuilder.new(
          team_id: @parent.id,
          viewer: @context[:viewer],
          membership: @arguments[:membership],
          role: @arguments[:role],
          query: @arguments[:query],
        )
      end

      def users_scope
        base_scope_builder.scope
      end
    end
  end
end
