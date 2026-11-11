# typed: true
# frozen_string_literal: true

module Platform
  module ConnectionWrappers
    class ProjectCardsArrayConnection < GraphQL::Pagination::ArrayConnection
      include Platform::ConnectionWrappers::PaginationValidation

      def initialize(
        relation,
        arguments: {},
        **kwargs
      )
        super(relation, arguments: arguments, **kwargs)
        @max_per_page = calculate_per_page_value(max_page_size.to_i)
        validate_arguments!
      end

      def cursor_for(item)
        idx = (after ? index_from_cursor(after) : 0) + sliced_nodes.find_index(item.id) + 1
        encode(idx.to_s)
      end

      def nodes
        @paged_nodes ||= begin
          item_ids = sliced_nodes
          item_ids = item_ids.first(first) if first
          item_ids = item_ids.last(last) if last
          item_ids = item_ids.first(max_page_size) if max_page_size && !first && !last

          cards = @items.where(id: item_ids)
          project = @parent.class.to_s == "ProjectColumn" ? @parent.project : @parent
          ProjectCard.redact_and_prefill(@context[:viewer], project, cards)
        end
      end

      def sliced_nodes
        @sliced_nodes ||= if numeric_page
          numeric_page_sliced_node_ids
        else
          cursor_sliced_node_ids
        end
      end

      private

      def card_ids
        @card_ids ||= @items.pluck(:id)
      end

      def numeric_page
        return @numeric_page if defined?(@numeric_page)
        if arguments.present? && arguments[:numeric_page].present?
          @numeric_page = arguments[:numeric_page] < 0 ? 0 : arguments[:numeric_page]
        end
      end

      def numeric_page_sliced_node_ids
        @numeric_page_sliced_node_ids ||= begin
          per_page = first
          last_page = (card_ids.size / per_page.to_f).ceil

          if numeric_page <= last_page
            offset = (per_page * (numeric_page - 1))
            card_ids.drop(offset)
          else
            []
          end
        end
      end

      def cursor_sliced_node_ids
        @cursor_sliced_node_ids ||= if before && after
          card_ids[index_from_cursor(after)..index_from_cursor(before) - 1] || []
        elsif before
          card_ids[0..index_from_cursor(before) - 2] || []
        elsif after
          card_ids[index_from_cursor(after)..-1] || []
        else
          card_ids
        end
      end
    end
  end
end
