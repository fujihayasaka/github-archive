# typed: strict
# frozen_string_literal: true

class Topics::SortComponent < ApplicationComponent
  include SearchHelper

  RENDER_COUNT_THRESHOLD = 10

  # We have to exclude the default blank sort option, since that is called "best match"
  # for regular searching. On the topic show page, we just default to sorting by stars
  # instead, since there is no "best match" when there isn't a search query.
  EXCLUDED_SORT_OPTION = T.let(["", "desc"], T::Array[String])

  sig { params(result_count: Integer, sort: String, direction: String).void }
  def initialize(result_count:, sort:, direction:)
    @result_count = result_count
    @sort         = sort
    @direction    = direction
  end

  private

  sig { returns(Integer) }
  attr_reader :result_count

  sig { returns(String) }
  attr_reader :sort

  sig { returns(String) }
  attr_reader :direction

  sig { returns(T::Boolean) }
  def render?
    result_count > RENDER_COUNT_THRESHOLD
  end

  sig { returns(T::Array[String]) }
  def sort_fields
    repo_search_sort_fields - [EXCLUDED_SORT_OPTION.first]
  end

  sig { returns(T::Hash[T::Array[String], String]) }
  def sort_labels
    repo_search_sort_labels.except(EXCLUDED_SORT_OPTION)
  end
end
