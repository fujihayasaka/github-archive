# typed: true
# frozen_string_literal: true

class Platform::Models::CodeSearchSnippet
  attr_reader :end_position,
    :ending_line_number,
    :jump_to_line_number,
    :lines,
    :match_count,
    :score,
    :start_position,
    :starting_line_number,
    :type

  def initialize(
    end_position:,
    ending_line_number:,
    jump_to_line_number:,
    match_count:,
    score:,
    start_position:,
    starting_line_number:,
    type:,
    lines: []
  )
    @end_position         = end_position
    @ending_line_number   = ending_line_number
    @type                 = type
    @jump_to_line_number  = jump_to_line_number
    @lines                = lines || []
    @match_count          = match_count
    @score                = score
    @start_position       = start_position
    @starting_line_number = starting_line_number
  end
end
