# typed: true
# frozen_string_literal: true

require "monolith-twirp-examples-octocat"

module Api::Internal::Twirp::Examples
  module Octocat
    module V1
      # Equivalent to Api::Internal::Twirp::Octocat::V1::OctocatAPIHandler,
      # just using a different service definition.
      class OctocatAPIHandler < Api::Internal::Twirp::Octocat::V1::OctocatAPIHandler
        allow_access_for :client, :user, allowed_clients: ["octocat"].freeze
        handles_service(MonolithTwirp::Examples::Octocat::V1::OctocatAPIService)
      end
    end
  end
end
