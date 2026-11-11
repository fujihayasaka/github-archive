# typed: true
# frozen_string_literal: true

require "monolith-twirp-examples-octocat"

module Api::Internal::Twirp::Examples
  module Octocat
    module V1
      class OctocatAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, :user, allowed_clients: ["octocat"].freeze
        handles_service(MonolithTwirp::Examples::Octocat::V1::OctocatAPIService)

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
