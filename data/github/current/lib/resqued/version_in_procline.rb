# typed: true
# frozen_string_literal: true

module Resqued
  module VersionInProcline
    PROCLINE_VERSION = "[#{GitHub.current_sha[0, 7]}] "

    def procline(string)
      super(PROCLINE_VERSION + string)
    end
  end
end
