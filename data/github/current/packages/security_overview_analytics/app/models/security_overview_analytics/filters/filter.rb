# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Filters
    # Used to generate a WHERE clause predicate for querying the Insights service
    module Filter
      extend T::Sig
      extend T::Helpers
      include Kernel # For methods like `is_a?`, `class`, etc.
      interface!

      sig { abstract.params(rel: ActiveRecord::Relation).returns(ActiveRecord::Relation) }
      def apply(rel); end

      sig { abstract.returns(T::Boolean) }
      def is_empty?; end

      sig { abstract.returns(T::Boolean) }
      def has_incl_filters?; end
    end
  end
end
