# typed: false
# frozen_string_literal: true

module Gists
  module ForkCountingMethods
    def fork_count
      forks.count
    end

    private

    def forks
      gist.visible_forks
    end
  end
end
