# typed: true
# frozen_string_literal: true

require "github-proto-octocat"

class Api::Internal::Twirp
  module Octocat
    module V1
      class OctocatAPIHandler < Api::Internal::Twirp::Handler
        handles_service(GitHub::Proto::Octocat::V1::OctocatAPIService)

        allow_access_for :client, :user, allowed_clients: ["octocat"].freeze

        def get_octocat(req, env)
          if Rails.env.test?
            env[:http_response_headers]["X-Handler-Object-Id"] = self.object_id

            if req.phrase == "boom!"
              raise "This error was raised on purpose, for testing."
            end
          end

          {
            octocat: generate_octocat(req.phrase)
          }
        end

        private

        def generate_octocat(phrase)
          if phrase =~ /\A[\w\- ,\/]*\z/
            GitHub.octocat(phrase)
          else
            GitHub.octocat
          end
        end
      end
    end
  end
end
