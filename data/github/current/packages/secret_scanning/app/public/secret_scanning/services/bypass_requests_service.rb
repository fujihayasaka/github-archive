# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Services
    class BypassRequestsService

      sig do
        params(
          exemption_request: Exemptions::ExemptionRequest,
          status: T.nilable(String),
          message: String,
          user: User,
          repo: Repository,
        ).returns([T.nilable(Exemptions::ExemptionResponse), T.nilable(String)])
      end
      def self.review_exemption_request!(exemption_request:, status:, message:, user:, repo:)
        if status == "approve"
          res = Exemptions::ExemptionResponse.approve!(exemption_request, user, message: message)
          GitHub.instrument("secret_scanning_push_protection_request.approve", {
            actor: user,
            repository: repo,
            org: repo.organization,
            number: exemption_request.number,
            request_reviewer_comment: message,
          })
        elsif status == "reject"
          res = Exemptions::ExemptionResponse.reject!(exemption_request, user, message: message)
          GitHub.instrument("secret_scanning_push_protection_request.deny", {
            actor: user,
            repository: repo,
            org: repo.organization,
            number: exemption_request.number,
            request_reviewer_comment: message,
          })
        else
          return nil, "Invalid status: #{status}"
        end
        [res, nil]
      end

      MSG_LIMIT = 2048
      sig { params(message: T.nilable(String)).returns([T::Boolean, T.nilable(String)]) }
      def self.validate_request_message(message)
        message ||= ""
        message = message.strip
        return false, "Message is required" if message.empty?
        return false, "Message exceeds #{MSG_LIMIT} character limit" if message.length > MSG_LIMIT
        [true, nil]
      end

    end
  end
end
