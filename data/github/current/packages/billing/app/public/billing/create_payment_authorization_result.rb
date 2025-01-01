# typed: strict
# frozen_string_literal: true

class Billing::CreatePaymentAuthorizationResult < T::Struct
  sig { params(reason: Reason).returns(T.attached_class) }
  def self.skipped(reason:)
    new(result: Result::Skipped, reason:)
  end

  sig { params(amount_authorized_in_cents: Integer).returns(T.attached_class) }
  def self.success(amount_authorized_in_cents:)
    new(result: Result::Success, amount_authorized_in_cents:)
  end

  sig { params(reason: Reason, amount_authorized_in_cents: Integer).returns(T.attached_class) }
  def self.failed(reason:, amount_authorized_in_cents: 0)
    new(result: Result::Failed, reason:, amount_authorized_in_cents:)
  end

  class Reason < T::Enum
    enums do
      Ineligible                = new
      RecentAuthorizationExists = new
      CannotBeAuthorized        = new
      AuthorizationFailure      = new
      EnqueueFailure            = new
    end
  end

  class Result < T::Enum
    enums do
      Success = new
      Failed  = new
      Skipped = new
    end
  end

  const :result, Result
  const :reason, T.nilable(Reason)
  const :amount_authorized_in_cents, Integer, default: 0

  sig { returns(T::Boolean) }
  def authorized?
    result == Result::Success
  end

  sig { returns(T::Boolean) }
  def skipped?
    result == Result::Skipped
  end

  sig { returns(T::Boolean) }
  def failed?
    result == Result::Failed
  end
end
