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
    path: nil,
    failed_count_message: nil
  )
    @icon = icon
    @count = count
    @singular = singular
    @max_threshold = max_threshold
    @path = path
    @failed_count_message = failed_count_message
  end

  def text
    return @failed_count_message if @failed_count_message.present? && @count.nil?

    delimited_count = number_with_delimiter(@count)
    max_threshold_marker = "+" if @max_threshold.present? && @count >= @max_threshold
    pluralized = @singular.pluralize(@count)
    "#{delimited_count}#{max_threshold_marker} #{pluralized}"
  end
end
