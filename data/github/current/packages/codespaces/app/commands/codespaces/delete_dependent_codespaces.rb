# typed: true
# frozen_string_literal: true

module Codespaces
  class DeleteDependentCodespaces < Command

    attr_reader :owner_id, :owner_type, :reason

    def initialize(owner_id:, reason:)
      @owner_id = owner_id
      @reason = reason
    end

    def perform
      codespaces = Codespace.where(owner_id: owner_id).or(Codespace.where(billable_owner_id: owner_id))

      codespaces.each do |codespace|
        Codespace.throttle_with_retry { codespace.deprovision!(reason: reason) }
      end
    end
  end
end
