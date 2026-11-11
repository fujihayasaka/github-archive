# frozen_string_literal: true

module HandleWebhook
  class IssueComment
    class HandleHeartRequest
      def initialize(pull_request:, comment_id:, comment_type:)
        @pull_request = pull_request
        @comment_id = comment_id
        @comment_type = comment_type
      end

      def run
        create_acknowledgement_reaction_if_possible
      end

      private

      attr_reader :pull_request, :comment_id, :comment_type

      def create_acknowledgement_reaction_if_possible
        CreateReaction.new(
          reaction: "heart",
          comment_id: comment_id,
          comment_type: comment_type,
          pull_request: pull_request,
        ).run
      end
    end
  end
end
