# typed: true
# frozen_string_literal: true

class Platform::Models::CodeSearchErrorRange
  attr_reader :start_position, :end_position

  def initialize(start_position:, end_position:)
    @start_position = start_position.to_i
    @end_position   = end_position.to_i
  end
end
