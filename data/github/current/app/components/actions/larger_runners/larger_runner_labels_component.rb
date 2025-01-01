# typed: true
# frozen_string_literal: true

module Actions
  class LargerRunners::LargerRunnerLabelsComponent < ApplicationComponent
    def initialize(larger_runner: Actions::LargerRunner.new)
      @labels = larger_runner.labels
      @runner_id = larger_runner.id
    end
  end
end
