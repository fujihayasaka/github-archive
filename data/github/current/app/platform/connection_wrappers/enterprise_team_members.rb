# typed: true
# frozen_string_literal: true

module Platform
  module ConnectionWrappers
    class EnterpriseTeamMembers < Relation
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
          query: arguments[:query],
          pagination: pagination_options,
          with_business_teams: true,
        ).scope
        if (ordering = arguments[:order_by])
          scope = scope.order("users.#{ordering[:field]} #{ordering[:direction]}")
        end
        @items, @orderings = Ordering.from_relation(scope)
      end

      def total_count
        base_scope_builder.count
      end

      def record_at_offset(page, last_page, offset)
        return super unless pagination_optimizations?

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
          ::Promise.resolve(async_user).then do |user|
            encode_cursor([user.id])
          end
        else
          super
        end
      end

      def pagination_options
        return {} unless pagination_optimizations?

        if after
          after_user_id = decode_cursor(after).first
        end

        if before
          before_user_id = decode_cursor(before).first
        end

        { first: first, last: last, before: before_user_id, after: after_user_id }
      end

      def pagination_optimizations?
        return false if @arguments[:query].present?

        order = @arguments[:order_by]
        order.blank? || (order[:field] == "id" && order[:direction].to_s.casecmp("asc").zero?)
      end

      private

      def base_scope_builder
        @base_scope_builder ||= ::Team::Membership::ScopeBuilder.new(
          team_id: @parent.id,
          viewer: @context[:viewer],
          query: @arguments[:query],
          with_business_teams: true,
        )
      end

      def users_scope
        base_scope_builder.scope
      end
    end
  end
end
