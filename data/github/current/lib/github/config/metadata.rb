# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module Metadata
      # Reads and parses /etc/github/metadata.json.
      def read_metadata
        File.open("/etc/github/metadata.json", "r") do |fh|
          GitHub::JSON.load(fh)
        end
      end
    end
  end

  extend Config::Metadata
end
