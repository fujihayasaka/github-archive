# typed: true
# frozen_string_literal: true

module Rest
  class Paginator
    # If the collection size is unknown, we cannot compute pagination.
    # For consistency we raise this on all methods related to navigation,
    # even if the value does not depend on the collection size.
    class CannotComputeError < StandardError; end

    attr_reader :page, :per_page, :default_per_page, :max_per_page
    attr_accessor :collection_size
    def initialize(page: 1, per_page: nil, default_per_page:, max_per_page:, collection_size: nil)
      @default_per_page = default_per_page
      @max_per_page     = max_per_page

      @page = begin
        [Integer(page), 1].max
      rescue TypeError, ArgumentError
        1
      end

      @per_page = begin
        Integer(per_page)
      rescue TypeError, ArgumentError
        default_per_page
      end
      @per_page = default_per_page if @per_page <= 0
      @per_page = max_per_page if @per_page > max_per_page

      @collection_size = collection_size
    end

    def first_page
      raise CannotComputeError unless collection_size_defined?

      1
    end

    def last_page
      raise CannotComputeError unless collection_size_defined?

      (effective_collection_size / per_page.to_f).ceil
    end

    def next_page
      raise CannotComputeError unless collection_size_defined?

      page + 1
    end

    def previous_page
      raise CannotComputeError unless collection_size_defined?

      if (first_page..last_page).cover? page
        page - 1
      else
        last_page
      end
    end

    def previous?
      raise CannotComputeError unless collection_size_defined?

      first_page < page
    end

    def next?
      raise CannotComputeError unless collection_size_defined?

      page < last_page
    end

    private

    def effective_collection_size
      [collection_size, 1].max
    end

    def collection_size_defined?
      !@collection_size.nil?
    end
  end
end
