# typed: true
# frozen_string_literal: true

module Actions
  class HostedRunners::HostedRunnersLabelsComponent < ApplicationComponent
    def initialize
      @labels = %w(windows-2022 windows-2025 windows-11-arm windows-latest ubuntu-22.04 ubuntu-24.04 ubuntu-latest macos-14-large macos-15 macos-15-intel macos-15-xlarge macos-latest macos-latest-large macos-latest-xl)
    end
  end
end
