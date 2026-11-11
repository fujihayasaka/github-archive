# typed: strict
# frozen_string_literal: true

module FeatureManagement
  module Models
    # Wrapper class to provide pagination compatibility for will_paginate
    class PaginatedDevtoolsActorsCollection
      delegate :each, :any?, :empty?, :length, :size, to: :@actors

      sig { params(actors: T::Array[GitHub::VexiActor], page: Integer, per_page: Integer).void }
      def initialize(actors, page: 1, per_page: 100)
        @current_page = T.let(page, Integer)
        @per_page = T.let(per_page, Integer)

        start_index = offset
        end_index = start_index + @per_page - 1
        @actors = T.let(actors[start_index..end_index] || [], T::Array[GitHub::VexiActor])
        @total_entries = T.let(actors.length, Integer)
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
