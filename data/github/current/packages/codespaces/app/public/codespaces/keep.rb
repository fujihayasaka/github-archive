# typed: strict
# frozen_string_literal: true

module Codespaces
  class Keep < Command

    sig { params(codespace: Codespace).void }
    def initialize(codespace)
      @codespace = codespace
    end

    sig { returns(T::Boolean) }
    def can_keep?
      !Codespaces::MaximumRetentionPeriodPolicy.exists?(
        billable_owner: codespace.billable_owner,
        repository: codespace.repository
      )
    end

    sig { override.returns(T.nilable(T::Boolean)) }
    def perform
      return unless can_keep?

      codespace.update!(keep: true)
    end

    private

    sig { returns(Codespace) }
    attr_reader :codespace
  end
end
