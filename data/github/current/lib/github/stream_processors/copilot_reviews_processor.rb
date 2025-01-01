# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    class CopilotReviewsProcessor < BaseProcessor
      extend T::Sig

      DEFAULT_GROUP_ID = "github-#{Rails.env}-copilot_reviews_processor"
      DEFAULT_SUBSCRIBE_TO = /github\.v1\.PullRequestCreate\Z/

      options[:session_timeout] = 60.seconds
      options[:socket_timeout] = 65.seconds
      options[:start_from_beginning] = false

      def setup(**kwargs)
        options[:group_id] ||= DEFAULT_GROUP_ID
        options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO
      end

      def process_message(message)
        payload = message.value

        actor = User.find_by(id: payload.dig(:actor, :id))
        return if actor.nil?

        repo = Repository.find_by(id: payload.dig(:repository, :id))
        return if repo.nil?

        code_review_access = PullRequests::Copilot::CodeReviewAccess.new(actor: actor, current_repository: repo)
        return unless code_review_access.auto_reviewable?

        pull = PullRequest.find_by(id: payload.dig(:pull_request, :id))
        return if pull.nil?

        app = ::Apps::Internal.integration(:copilot_pull_request_reviewer)
        return if app.nil?

        # Automatic reviews: create a review request,
        # which will trigger the HydroFulfillCopilotReviewRequestJob.
        ActiveRecord::Base.connected_to(role: :writing) do
          pull.add_pending_reviewer(app.bot)
          pull.save
        end
      end
    end
  end
end
