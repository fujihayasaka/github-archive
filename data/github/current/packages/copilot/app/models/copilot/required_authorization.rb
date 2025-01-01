# typed: strict
# frozen_string_literal: true

module Copilot
  class RequiredAuthorization < ApplicationRecord::Copilot
    extend T::Sig
    include ::Instrumentation::Model
    include Copilot::Helpers

    self.table_name = "copilot_required_authorizations"
    self.strict_loading_by_default = true

    belongs_to :owner, polymorphic: true, strict_loading: false
    validates :owner, presence: true

    scope :active, -> { where(state: "active") }
    scope :pending_token, -> { where(state: "pending_token") }
    scope :for_organizations, -> (ids) { where(owner_type: "Organization", owner_id: ids) }

    enum :state, {
      active: 0,
      pending_token: 1,
    }, default: :active
  end
end
