# typed: true
# frozen_string_literal: true

module Codespaces
  class DeleteDependentNeverAvailableCodespaces < Command

    attr_reader :owner_id

    def initialize(owner_id:)
      @owner_id = owner_id
    end

    def perform
      codespaces = Codespace.where(owner_id: owner_id).or(Codespace.where(billable_owner_type: "User", billable_owner_id: owner_id))

      codespaces.each do |codespace|
        Codespace.throttle_with_retry { codespace.deprovision!(reason: Codespace.deletion_reasons[:dependent_never_available]) } if codespace.never_available?
      end
    end
  end
end
