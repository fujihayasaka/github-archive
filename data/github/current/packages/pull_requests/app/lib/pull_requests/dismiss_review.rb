# typed: strict
# frozen_string_literal: true

module PullRequests
  module DismissReview
    class Success < T::Struct
    end

    class Error < T::Struct
      NotPermitted = Class.new
      ValidationError = Class.new
      Unprocessable = Class.new

      const :error_message, T.nilable(String)
      const :failure_reason, T.any(NotPermitted, ValidationError, Unprocessable)
    end

    sig do
      params(
        review: PullRequestReview,
        user: User,
        message: T.nilable(String),
      ).returns(T.any(Success, Error))
    end
    def self.execute(review:, user:, message:)
      if !review.can_be_dismissed_by?(user)
        return Error.new(error_message: "You are not allowed to dismiss this review.", failure_reason: Error::NotPermitted.new)
      end

      unless review.can_trigger?(:dismiss)
        state = PullRequestReview.state_name(review.state)
        return Error.new(error_message: "Cannot dismiss a #{state} review.", failure_reason: Error::ValidationError.new)
      end

      if message.blank?
        return Error.new(error_message: "A message is required to dismiss a pull request review.", failure_reason: Error::ValidationError.new)
      end

      review.trigger(:dismiss, actor: user, message: message)

      if review.persisted?
        Success.new
      else
        Error.new(error_message: "Could not dismiss pull request review.", failure_reason: Error::Unprocessable.new)
      end
    end
  end
end
