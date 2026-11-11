# typed: true
# frozen_string_literal: true

require "monolith-twirp-pullsd-pullrequestinfo"

module Api::Internal::Twirp::Pullsd
  module Pullrequestinfo
    module V1
      # Handler for the MonolithTwirp::Pullsd::PullRequestInfo::V1::PullRequestInfoAPIService
      class PullRequestInfoAPIHandler < Api::Internal::Twirp::Handler
        include Api::Internal::Twirp::Pullsd::Shared::ViewerResolver

        allow_access_for :client, allowed_clients: ["pullsd"]
        handles_service MonolithTwirp::Pullsd::PullRequestInfo::V1::PullRequestInfoAPIService

        # Public: Implementation of the ManyById Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Pullsd::PullRequestInfo::V1::ManyByIdRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Pullsd::PullRequestInfo::V1::ManyByIdResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Pullsd::PullRequestInfo::V1::ManyByIdRequest,
            env: T::Hash[String, T.untyped]
          ).returns(T.any(MonolithTwirp::Pullsd::PullRequestInfo::V1::ManyByIdResponse, Twirp::Error))
        end
        def many_by_id(req, env)
          pull_request_ids = req.pull_request_ids.to_a

          if pull_request_ids.empty?
            return MonolithTwirp::Pullsd::PullRequestInfo::V1::ManyByIdResponse.new
          end

          pull_requests = PullRequest.where(id: pull_request_ids).to_a

          if pull_requests.empty?
            return Twirp::Error.not_found("no pull requests found for the given IDs")
          end

          viewer = resolve_viewer(
            viewer_id: req.viewer_id,
            installation_id: req.installation_id,
            installation_type: req.installation_type,
            oauth_access_id: req.oauth_access_id,
          )

          IssuePrefiller.optimized_preload_author_associations(pull_requests, viewer)

          # When the monolith-side feature flag is enabled, honor the
          # include_diff_stats field from the request. When the field is
          # false, skip DiffStats computation since pullsd computes these
          # directly from Spokes. The feature flag gates this behavior so
          # the monolith can be deployed before all pullsd instances send
          # include_diff_stats=true, and can be reverted without a redeploy.
          skip_diff_stats = !req.include_diff_stats &&
            FeatureFlag.vexi.enabled?(:pullsd_skip_diff_stats_in_monolith, default: false)

          MonolithTwirp::Pullsd::PullRequestInfo::V1::ManyByIdResponse.new(
            pull_request_infos: pull_requests.map do |pull|
              diff_stats = if skip_diff_stats
                { commits: 0, additions: 0, deletions: 0, changed_files: 0 }
              else
                begin
                  pull.set_diff_options(timeout: Api::Pulls::GIT_SUMMARY_TIMEOUT_SECS) if T.must(pull.repository).feature_flag_enabled?(:pull_api_diff_timeout, default: false)

                  Api::Serializer::PullRequest::DiffStats.new(pull_request: pull).call
                rescue GitRPC::Timeout, SpokesAPI::TimedOut, SpokesAPI::Canceled => e
                  GitHub.logger.error("PullRequestInfoAPIHandler: diff stats failed for PR #{pull.id}", exception: e)
                  return Twirp::Error.failed_precondition("The request could not be processed because too many files changed")
                rescue GitRPC::InvalidObject, GitRPC::ObjectMissing, SpokesAPI::NotFound, SpokesAPI::InvalidArgument => e
                  GitHub.logger.warn("PullRequestInfoAPIHandler: PR not found for #{pull.id}", exception: e)
                  return Twirp::Error.not_found("pull request not found")
                end
              end

              info = {
                pull_request_id: pull.id,
                mergeable: pull.currently_mergeable?,
                rebaseable: pull.currently_mergeable? && pull.rebase_safe?,
                mergeable_state: pull.merge_state(viewer: viewer).status,
                commits: diff_stats[:commits],
                additions: diff_stats[:additions],
                deletions: diff_stats[:deletions],
                changed_files: diff_stats[:changed_files],
                author_association: pull.author_association_symbol(viewer).to_s.upcase,
              }

              if req.include_body_html
                info[:body_html] = String.new(pull.body_html || "")
              end

              if req.include_body_text
                info[:body_text] = pull.body_text || ""
              end

              MonolithTwirp::Pullsd::PullRequestInfo::V1::PullRequestInfo.new(**info)
            end

          )
        end
      end
    end
  end
end
