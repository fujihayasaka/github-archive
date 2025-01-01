# typed: false
# frozen_string_literal: true

module Platform
  module ConnectionWrappers
    module PaginationValidation
      # Override the base method because it does not check if the context is present
      def max_page_size
        if @has_max_page_size_override
          @max_page_size
        else
          context.present? && context.dig(:context, :schema, :default_max_page_size) ? context.schema.default_max_page_size : Platform::Schema::DEFAULT_MAX_PER_PAGE
        end
      end

      def calculate_per_page_value(page_size)
        raise Platform::Errors::MaxPageSizeExceeded.new(page_size) if page_size > Platform::Schema::ABSOLUTE_MAX_PER_PAGE && !@disable_max_page_size_validation
        page_size = Platform::Schema::DEFAULT_MAX_PER_PAGE if page_size <= 0
        page_size
      end

      def validate_arguments!
        if @first_value && @last_value
          raise Platform::Errors::DuplicateFirstLastPaginationBoundaries.new(@field)
        end

        if @first_value
          if @first_value > @max_per_page
            raise Platform::Errors::ExcessivePagination.new(@field, :first, @first_value, @max_per_page)
          elsif @first_value < 0
            raise Platform::Errors::InvalidPagination.new(@field, :first)
          end
        end

        if @last_value
          if @last_value > @max_per_page
            raise Platform::Errors::ExcessivePagination.new(@field, :last, @last_value, @max_per_page)
          elsif @last_value < 0
            raise Platform::Errors::InvalidPagination.new(@field, :last)
          end
        end

        if @after_value && @arguments.present? && @arguments[:numeric_page]
          raise Platform::Errors::ConflictingPaginationArguments.new(@field)
        end
      end
    end
  end
end
