# typed: strict
# frozen_string_literal: true

module Copilot
  class AdministrativeBlock < ApplicationRecord::Copilot
    extend T::Sig
    include ::Instrumentation::Model
    include Copilot::Helpers

    self.table_name = "copilot_administrative_blocks"
    self.strict_loading_by_default = true

    belongs_to :blockable, polymorphic: true, strict_loading: false
    # rubocop:todo Rails/InverseOf
    belongs_to :actor, class_name: "::User", foreign_key: :actor_id, strict_loading: false
    # rubocop:enable Rails/InverseOf

    validates :actor, presence: true
    validates :blockable, presence: true

    enum :state, {
      active: 0,
      revoked: 1,
      warned: 2,
    }

    ACTIVE_STATE = "blocked"
    REVOKED_STATE = "unblocked"
    WARNED_STATE = "warned"
  end
end
