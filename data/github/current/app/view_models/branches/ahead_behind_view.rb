# typed: false
# frozen_string_literal: true

require "github/log_scale"

module Branches
  class AheadBehindView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    include CompareHelper

    def initialize(*args)
      super(*args)
    end

    attr_reader :ahead_behind, :max_diverged, :repository

    def ahead_behind_count
      return "" if ahead_behind.nil?

      ahead, behind = ahead_behind
      compare_ahead_behind_text(ahead, behind, base_branch: repository.default_branch)
    end

    def behind_count
      if ahead_behind
        ahead, behind = ahead_behind
        behind
      end
    end

    def ahead_count
      if ahead_behind
        ahead, behind = ahead_behind
        ahead
      end
    end

    def behind_count_class
      "even" if behind_count == 0 if ahead_behind
    end

    def ahead_count_class
      "even" if ahead_count == 0 if ahead_behind
    end

    def ahead_percent
      scale.call(ahead_count).round(2)
    end

    def behind_percent
      scale.call(behind_count).round(2)
    end

    private

    def scale
      @scale ||= GitHub::LogScale.scale!(domain: [1, max_diverged], range: [0, 80])
    end
  end
end
