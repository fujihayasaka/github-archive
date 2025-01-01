# typed: true
# frozen_string_literal: true

module Actions
  class HostedRunners::HostedRunnersLabelsComponent < ApplicationComponent
    def initialize
      @labels = %w(windows-2019 windows-2022 windows-latest ubuntu-20.04 ubuntu-22.04 ubuntu-latest macos-11 macos-12 macos-12-xl macos-13 macos-13-xl macos-latest macos-latest-xl)
    end
  end
end
