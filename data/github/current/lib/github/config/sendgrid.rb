# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module Sendgrid
      def self.api_key
        ENV["SENDGRID_API_KEY"]
      end
    end
  end
end
