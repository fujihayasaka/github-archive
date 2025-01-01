# typed: strict
# frozen_string_literal: true

module ApiInsights::Stats
  class ErrorCode < T::Enum

    enums do
      TIMESTAMP_RANGE_NEGATIVE = new
      TIMESTAMP_RANGE_TOO_LARGE = new
      INVALID_SORT_FIELD = new
      FILTERS_NOT_SPECIFIED = new
      SUMMARY_FIELDS_NOT_SPECIFIED = new
      SORT_DEFINITIONS_NOT_SPECIFIED_WHEN_PAGING = new
      PAGER_INVALID_MIN_ROW = new
      PAGER_INVALID_MAX_ROW = new
      PAGER_MIN_ROW_AFTER_MAX_ROW = new
      PAGER_INVALID_PAGE = new
      PAGER_INVALID_PAGE_SIZE = new
      INVALID_TIMESTAMP_INCREMENT = new
      TAKE_INVALID_MIN = new
      TAKE_INVALID_MAX = new
    end

    sig { returns String }
    def to_error_message
      case self
      when TIMESTAMP_RANGE_NEGATIVE then "The minimum timestamp specified is after the maximum timestamp resulting in an invalid range."
      when TIMESTAMP_RANGE_TOO_LARGE then "The time range specified is too large."
      when INVALID_SORT_FIELD then "The sort field specified is invalid."
      when FILTERS_NOT_SPECIFIED then "Filters were not specified and are required."
      when SUMMARY_FIELDS_NOT_SPECIFIED then "Summary fields were not specified and are required."
      when SORT_DEFINITIONS_NOT_SPECIFIED_WHEN_PAGING then "Sort definitions not specified and are required when paging."
      when PAGER_INVALID_MIN_ROW then "The minimum row specified for the pager is invalid. It must be greater than 0."
      when PAGER_INVALID_MAX_ROW then "The maximum row specified for the pager is invalid. It must be greater than 0."
      when PAGER_MIN_ROW_AFTER_MAX_ROW then "The minimum row specified is after the maximum row, resulting in an invalid range."
      when PAGER_INVALID_PAGE then "The page number specified for the pager is invalid. It must be greater than 0."
      when PAGER_INVALID_PAGE_SIZE then "The page size specified for the pager is invalid. It must be greater than 0."
      when INVALID_TIMESTAMP_INCREMENT then "The specified timestamp increment is invalid."
      when TAKE_INVALID_MIN then "The take value specified is invalid. It must be greater than 0."
      when TAKE_INVALID_MAX then "The take value specified is invalid. It must be less than or equal to 100."
      else
        T.absurd(self)
      end
    end
  end
end
