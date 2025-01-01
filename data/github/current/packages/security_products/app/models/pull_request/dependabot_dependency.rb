# typed: true
# frozen_string_literal: true

class PullRequest
  module DependabotDependency
    extend ActiveSupport::Concern
    extend T::Helpers

    CHECK_RUN_NAME = "Copilot Autofix"

    requires_ancestor { PullRequest }

    included do
      T.bind(self, T.class_of(PullRequest))
    end

    def dependabot_annotation_for_review_comment(pull_request_review_comment)
      annotation = dependabot_check_annotation(pull_request_review_comment)

      return annotation if annotation&.dependabot_annotation.present?

      # Log and Return nil if no annotation is found
      log_warning(
        "No dependabot annotation found for the comment",
        "dependabot_annotation_for_review_comment",
        pull_request_review_comment.id,
        pull_request_review_comment.repository_id
      )
      nil
    end

    def dependabot_review_comment_for_comment(pull_request_review_comment, pull_request_number)
      # Check if the review comment is created by Dependabot
      if dependabot_bot.id == pull_request_review_comment.user.id
        annotation = dependabot_check_annotation(pull_request_review_comment)

        return DependabotReviewComment.new(
          id: annotation.id,
          autofix_job_id: annotation.dependabot_annotation&.autofix_job_id,
          warning_level: annotation.warning_level,
          fallback_annotation_title: "Fix breaking changes caused by dependency update",
          fallback_annotation_message: "Breaking changes caused by dependency update",
          pull_request_review_comment: pull_request_review_comment,
          pull_request_number: pull_request_number
        )
      end

      # Log and Return nil if no Dependabot review comment is found
      log_warning(
        "No dependabot review comment found",
        "dependabot_review_comment_for_comment",
        pull_request_review_comment.id,
        pull_request_review_comment.repository_id,
        pull_request_review_comment.user.display_login
      )
      nil
    end

    def dependabot_suggested_fix_autofix_job(dependabot_review_comment)
      return nil unless dependabot_review_comment.autofix_job_id.present?
      dependabot_suggested_fix(dependabot_review_comment)&.values&.first
    end

    def dependabot_suggested_fix(dependabot_review_comment)
      return nil unless dependabot_review_comment.autofix_job_id.present?

      suggested_fix = async_dependabot_suggested_fixes(dependabot_review_comment).sync
      return nil unless suggested_fix

      { dependabot_review_comment.autofix_job_id => suggested_fix }
    end

    def async_dependabot_suggested_fixes(dependabot_review_comment)
      if dependabot_review_comment.autofix_job_id.nil?
        return Promise.resolve(empty_dependabot_suggested_fix_response.suggested_fix)
      end

      Promise.resolve(
        Dependabot::Twirp.suggested_fixes_client.get_suggested_fix(
          autofix_job_id: dependabot_review_comment.autofix_job_id,
          github_pull_request_number: dependabot_review_comment.pull_request_number,
          github_repo_id: dependabot_review_comment.pull_request_review_comment.repository_id,
        )
      ).then do |response|
        if response.nil? || response.suggested_fix.nil?
          GitHub.logger.error(
            "Dependabot suggested fix response was nil",
            "code.namespace" => "PullRequest::DependabotDependency",
            "code.function" => "async_dependabot_suggested_fixes",
            "autofix_job_id" => dependabot_review_comment.autofix_job_id,
            "gh.pull_request_number" => dependabot_review_comment.pull_request_number,
            "gh.pull_request_id" => dependabot_review_comment.pull_request_review_comment.pull_request_id,
            "gh.repository_id" => dependabot_review_comment.pull_request_review_comment.repository_id
          )
          empty_dependabot_suggested_fix_response.suggested_fix
        else
          response.suggested_fix
        end
      end
    rescue Dependabot::Twirp::BaseError => e
      GitHub.logger.error(
        "Dependabot suggested fix service error",
        "exception.message" => e.message,
        "code.namespace" => "PullRequest::DependabotDependency",
        "code.function" => "async_dependabot_suggested_fixes",
        "autofix_job_id" => dependabot_review_comment.autofix_job_id,
        "gh.pull_request_number" => dependabot_review_comment.pull_request_number,
        "gh.pull_request_id" => dependabot_review_comment.pull_request_review_comment.pull_request_id,
        "gh.repository_id" => dependabot_review_comment.pull_request_review_comment.repository_id
      )

      Failbot.report!(e)

      Promise.resolve(empty_dependabot_suggested_fix_response.suggested_fix)
    end

    def empty_dependabot_suggested_fix_response
      DependabotApi::V1::GetSuggestedFixResponse.new
    end

    def dependabot_check_annotation(pull_request_review_comment)
      return @dependabot_check_annotation if defined?(@dependabot_check_annotation)

      check_run = CheckRun.for_sha_and_repository_id(
        pull_request_review_comment.pull_request_review.head_sha,
        pull_request_review_comment.repository_id).find_by(name: CHECK_RUN_NAME)

      @dependabot_check_annotation ||= CheckAnnotation.find_by(repository_id: pull_request_review_comment.repository_id, check_run_id: T.must(check_run).id)
    end

    def dependabot_bot
      return @dependabot_bot if defined?(@dependabot_bot)

      dependabot_app = Apps::Privileged.integration(:dependabot) or fail "dependabot integration not installed!"
      @dependabot_bot = dependabot_app.bot
    end

    private

    def log_warning(message, function_name, comment_id, repo_id, user_login = nil)
      log_data = {
        "code.namespace" => "PullRequest::DependabotDependency",
        "code.function" => function_name,
        "pull_request_review_comment_id" => comment_id,
        "gh.repository_id" => repo_id
      }
      log_data["user_display_login"] = user_login if user_login

      GitHub.logger.warn(message, log_data)
    end
  end
end
