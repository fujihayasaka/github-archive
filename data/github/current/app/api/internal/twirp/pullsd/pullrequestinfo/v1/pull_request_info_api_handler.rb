# typed: true
# frozen_string_literal: true

require "monolith-twirp-pullsd-pullrequestinfo"

module Api::Internal::Twirp::Pullsd
  module Pullrequestinfo
    module V1
      # Handler for the MonolithTwirp::Pullsd::PullRequestInfo::V1::PullRequestInfoAPIService
      class PullRequestInfoAPIHandler < Api::Internal::Twirp::Handler
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

          viewer = User.find_by(id: req.viewer_id)

          IssuePrefiller.optimized_preload_author_associations(pull_requests, viewer)

          MonolithTwirp::Pullsd::PullRequestInfo::V1::ManyByIdResponse.new(
            pull_request_infos: pull_requests.map do |pull|
              begin
                pull.set_diff_options(timeout: Api::Pulls::GIT_SUMMARY_TIMEOUT_SECS) if T.must(pull.repository).feature_flag_enabled?(:pull_api_diff_timeout, default: false)

                diff_stats = Api::Serializer::PullRequest::DiffStats.new(pull_request: pull).call
              rescue GitRPC::Timeout => e
                return Twirp::Error.deadline_exceeded("failed to fetch gitrpc data for pull request #{pull.id}: #{e.class.name}, #{e.message}")
              rescue GitRPC::InvalidObject, GitRPC::ObjectMissing => e
                return Twirp::Error.not_found("failed to fetch gitrpc data for pull request #{pull.id}: #{e.class.name}, #{e.message}")
              end

              MonolithTwirp::Pullsd::PullRequestInfo::V1::PullRequestInfo.new(
                pull_request_id: pull.id,
                mergeable: pull.currently_mergeable?,
                rebaseable: pull.currently_mergeable? && pull.rebase_safe?,
                mergeable_state: pull.merge_state(viewer: viewer).status,
                commits: diff_stats[:commits],
                additions: diff_stats[:additions],
                deletions: diff_stats[:deletions],
                changed_files: diff_stats[:changed_files],
                author_association: pull.author_association_symbol(viewer).to_s.upcase,
              )
            end

          )
        end
      end
    end
  end
end
