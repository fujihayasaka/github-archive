# typed: true
# frozen_string_literal: true

require "munger/client"

module GitHub
  module Config
    module Munger
      def munger
        @munger ||= ::Munger::Client.new(GitHub.munger_url)
      end
    end
  end

  extend Config::Munger
end
