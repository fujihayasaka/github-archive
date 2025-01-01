# typed: true
# frozen_string_literal: true

require "monolith-twirp-copilotapi-code_review"

module Api::Internal::Twirp::Copilotapi
  module CodeReview
    module V1
      # Handler for the MonolithTwirp::Copilotapi::CodeReview::V1::CodeReviewApiHandler
      class CodeReviewApiHandler < Api::Internal::Twirp::Handler
        extend T::Sig

        allow_access_for :client, allowed_clients: ["copilot_api"]
        handles_service MonolithTwirp::Copilotapi::CodeReview::V1::CodeReviewAPIService

        def create_review_comments(req, env)
          return Twirp::Error.not_found("repo_owner is not present", argument: "repo_owner") if !req.repo_owner.present?
          return Twirp::Error.not_found("repo_name is not present", argument: "repo_name") if !req.repo_name.present?

          nwo = "#{req.repo_owner}/#{req.repo_name}"
          repo = Repository.with_name_with_owner(nwo)
          return Twirp::Error.not_found("repo not found", argument: "repo_name") if repo.nil?

          pull = repo.issues.find_by_number(req.pull_number)&.pull_request
          return Twirp::Error.not_found("pull request not found", argument: "pull_number") if pull.nil?

          comments = req.comments.map(&:to_h)

          response = T.let({ status: "success" }, { status: String })
          creator_result = PullRequests::Copilot::CodeReviewCreator.new(
            pull:,
            repo:,
            commit_id: req.commit_id,
            comments: comments,
            body: req.body,
            diff_start_commit_oid: req.comparison_start_oid,
            diff_end_commit_oid: req.comparison_end_oid,
            diff_base_commit_oid: req.comparison_base_oid,
          ).create

          response = { status: "error" } unless creator_result
          response
        end
      end
    end
  end
end
