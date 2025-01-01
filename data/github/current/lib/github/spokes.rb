# typed: true
# frozen_string_literal: true

module GitHub
  module Spokes
    class ClientError < StandardError; end

    autoload :Client,      "github/spokes/client"

    def self.client
      @spokes_client ||= GitHub::Spokes::Client.new
    end
  end
end
