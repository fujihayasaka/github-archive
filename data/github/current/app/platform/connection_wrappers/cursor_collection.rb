# typed: strict
# frozen_string_literal: true

module Platform
  module ConnectionWrappers
    class CursorCollection < ConnectionWrappers::Base
      extend T::Generic
      extend T::Sig

      include GitHub::Memoizer

      Elem = type_member { { upper: BasicObject } }

      sig { returns(T::Array[Elem]) }
      memoize def nodes
        items.to_a
      end

      sig { returns(Integer) }
      memoize def total_count
        items.total_entries
      end

      sig { returns(T::Boolean) }
      memoize def has_next_page
        items.has_next_page?
      end

      sig { returns(T::Boolean) }
      memoize def has_previous_page
        items.has_previous_page?
      end

      sig { params(item: Elem).returns(T.nilable(String)) }
      def cursor_for(item)
        items.cursor_for(item)
      end

      sig { returns(GH::Domain::CursorCollection[Elem]) }
      def items
        T.cast(super, GH::Domain::CursorCollection[Elem])
      end
    end
  end
end
