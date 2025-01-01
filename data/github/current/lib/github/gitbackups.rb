# typed: true
# frozen_string_literal: true

module GitHub
  module Gitbackups
    class ClientError < StandardError; end

    autoload :Client,      "github/gitbackups/client"

    def self.client
      @gitbackups_client ||= GitHub::Gitbackups::Client.new
    end
  end
end
