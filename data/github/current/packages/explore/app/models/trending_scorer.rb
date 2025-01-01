# typed: true
# frozen_string_literal: true

require "github/linear_scale"

module TrendingScorer
  STAR_MIN = 2.0
  STAR_MAX = 5.0

  FOLLOW_MIN = 4.0
  FOLLOW_MAX = 6.0

  FORKS_MIN = 1.0
  FORKS_MAX = 4.0
end
