# typed: true
# frozen_string_literal: true

module Actions
  module Runners
    class CodeComponent < ApplicationComponent

      def initialize(platform:, commands:)
        @platform, @commands = platform, commands
      end

      def dom_id(command)
        "clipboard-copy-content-#{@platform}-#{command[:desc].parameterize}"
      end
    end
  end
end
