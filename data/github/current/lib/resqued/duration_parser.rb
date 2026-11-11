# typed: true
# frozen_string_literal: true

module Resqued
  class DurationParser
    TOKENS = {
      "s" => (1),
      "m" => (60),
      "h" => (60 * 60),
      "d" => (60 * 60 * 24)
    }

    def validate(input)
      input =~ /\A((\d+)[smhd][[:space:]]?)+\z/
    end

    def get_duration_in_seconds(input)
      time = 0
      input.scan(/(\d+)(\w)/).each do |amount, measure|
        time += amount.to_i * TOKENS[measure]
      end
      time
    end
  end
end
