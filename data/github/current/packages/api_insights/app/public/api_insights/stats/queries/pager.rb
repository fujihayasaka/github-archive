# typed: strict
# frozen_string_literal: true

module ApiInsights::Stats::Queries
  class Pager

    MAX_PER_PAGE = 100

    MIN_ROW_PAREMETER_NAME = "min_row_param"
    private_constant :MIN_ROW_PAREMETER_NAME

    MAX_ROW_PAREMETER_NAME = "max_row_param"
    private_constant :MAX_ROW_PAREMETER_NAME

    sig { returns(Integer) }
    attr_reader :min_row

    sig { returns(Integer) }
    attr_reader :max_row

    private

    sig { params(min_row: Integer, max_row: Integer).void }
    def initialize(min_row, max_row)
      @min_row = min_row
      @max_row = max_row
    end

    public

    sig { params(min_row: Integer, max_row: Integer).returns(Pager) }
    def self.from_rows(min_row, max_row)
      raise Error.new(ErrorCode::PAGER_INVALID_MIN_ROW, min_row:) if min_row < 1
      raise Error.new(ErrorCode::PAGER_INVALID_MAX_ROW, max_row:) if max_row < 1
      raise Error.new(ErrorCode::PAGER_MIN_ROW_AFTER_MAX_ROW, min_row:, max_row:) if min_row > max_row

      new(min_row, max_row)
    end

    sig { params(page: Integer, per_page: Integer).returns(Pager) }
    def self.from_page(page, per_page)
      raise Error.new(ErrorCode::PAGER_INVALID_PAGE, page:, allowed_min_value: 1) if page < 1
      raise Error.new(ErrorCode::PAGER_INVALID_PAGE_SIZE, per_page:, allowed_min_value: 1, allowed_max_value: MAX_PER_PAGE) if per_page < 1
      raise Error.new(ErrorCode::PAGER_INVALID_PAGE_SIZE, per_page:, max_page_size: MAX_PER_PAGE, allowed_min_value: 1, allowed_max_value: MAX_PER_PAGE) if per_page > MAX_PER_PAGE

      min_row = (page - 1) * per_page + 1
      max_row = page * per_page
      new(min_row, max_row)
    end

    sig { returns(String) }
    def to_s
      to_filter_condition
    end

    sig { returns(String) }
    def to_filter_condition
      "row_number() between (#{MIN_ROW_PAREMETER_NAME}..#{MAX_ROW_PAREMETER_NAME})"
    end

    sig { returns(T::Hash[String, Integer]) }
    def parameters
      {
        MIN_ROW_PAREMETER_NAME => @min_row,
        MAX_ROW_PAREMETER_NAME => @max_row
      }
    end
  end
end
