# typed: true
# frozen_string_literal: true

class Stafftools::SummaryCounterComponent < ApplicationComponent
  attr_reader :icon, :path

  renders_one :after_counter

  def initialize(
    icon:,
    count:,
    singular:,
    max_threshold: nil,
    path: nil
  )
    @icon = icon
    @count = count
    @singular = singular
    @max_threshold = max_threshold
    @path = path
  end

  def text
    delimited_count = number_with_delimiter(@count)
    max_threshold_marker = "+" if @max_threshold.present? && @count >= @max_threshold
    pluralized = @singular.pluralize(@count)
    "#{delimited_count}#{max_threshold_marker} #{pluralized}"
  end
end
