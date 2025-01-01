# typed: true
# frozen_string_literal: true

require "monolith-twirp-insights-auth"

module Api::Internal::Twirp::Insights
  module Auth
    module V1
      # Handler for the MonolithTwirp::Insights::Auth::V1::AuthAPIService
      class AuthAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["insights"]
        handles_service MonolithTwirp::Insights::Auth::V1::AuthAPIService

        def perform_cap_checks(req, env)
          GitHub.tracer.in_span("#{self.class.name}##{__method__}", kind: :internal, attributes: {
            GitHub::TaggingHelper::CATALOG_SERVICE_TAG => "github/insights",
            "insights.repository_request_count" => req.repo_ids.length
          }) do |_span|
            track_metrics(req) do
              session = UserSession.find_by(id: req.session_id)
              actor = session&.user || User.with_oauth_token(req.access_token)
              return Twirp::Error.not_found("user was not found from provided session id or access token") unless actor

              # map repos to orgs for CAP checks outside of ConditionalAccess::Model::Filter
              # this is for perf reasons - we don't want to hydrate a large number of repository objects
              # only to map them to their owning organization.
              # long term this endpoint should accept the org ids directly and the repo<>org mapping should
              # be done by the calling Insights service
              repo_and_owner_ids = Repository.where(id: req.repo_ids.to_a).pluck(:id, :owner_id)
              owner_repo_map = repo_and_owner_ids.each_with_object({}) do |(repo_id, org_id), hsh|
                (hsh[org_id] ||= []) << repo_id
              end

              filter = ConditionalAccess::Model::Filter.new(
                self, web_session: session, actor: actor, remote_ip: req.user_ip, location: :twirp_api)

              # filter the organizations
              authorized_owner_ids = filter.authorized_resource_ids(User.where(id: owner_repo_map.keys).to_a)

              # map the authorized orgs back to the corresponding passed in repos for the response
              {
                authorized_repo_ids: authorized_owner_ids.flat_map { |owner_id| owner_repo_map[owner_id] }
              }
            end
          end
        end

        def track_metrics(req, tags = [])
          start_time = GitHub::Dogstats.monotonic_time
          result = yield
          elapsed = GitHub::Dogstats.duration(start_time)

          GitHub.dogstats.distribution("insights.monolith.perform_cap_checks.request.repo_ids.length", req.repo_ids.length)

          if result.instance_of?(Twirp::Error)
            tags = tags.append("result:failure")
          else
            tags = tags.append("result:success")
          end

          GitHub.dogstats.distribution("insights.monolith.perform_cap_checks.request.duration.ms", elapsed, tags: tags)

          result
        end
      end
    end
  end
end
