# typed: strict
# frozen_string_literal: true

module FeatureManagement
  module Models
    # Wrapper class to provide pagination compatibility for will_paginate
    class PaginatedDevtoolsFeaturesCollection
      delegate :each, :any?, :empty?, :length, :size, to: :@features

      sig { params(features: T::Array[DevtoolsFeature], page: Integer, per_page: Integer, total_entries: T.nilable(Integer)).void }
      def initialize(features, page: 1, per_page: 100, total_entries: nil)
        @features = T.let(features, T::Array[DevtoolsFeature])
        @current_page = T.let(page, Integer)
        @per_page = T.let(per_page, Integer)
        @total_entries = T.let(total_entries || features.length, Integer)
      end

      # --- For will_paginate compatibility ---
      sig { returns(Integer) }
      attr_reader :total_entries

      sig { returns(Integer) }
      attr_reader :current_page, :per_page

      sig { returns(Integer) }
      def total_pages
        (@total_entries.to_f / @per_page).ceil
      end

      sig { returns(T.nilable(Integer)) }
      def previous_page
        @current_page > 1 ? @current_page - 1 : nil
      end

      sig { returns(T.nilable(Integer)) }
      def next_page
        @current_page < total_pages ? @current_page + 1 : nil
      end

      sig { returns(Integer) }
      def offset
        (@current_page - 1) * @per_page
      end
    end
  end
end
