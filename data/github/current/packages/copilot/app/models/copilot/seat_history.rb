# typed: strict
# frozen_string_literal: true

module Copilot
  class SeatHistory < ApplicationRecord::Copilot
    include ::Instrumentation::Model
    include Copilot::Helpers

    self.table_name = "copilot_seat_histories"
    self.strict_loading_by_default = true
    self.ignored_columns += [:copilot_plan]

    belongs_to :owner, polymorphic: true, strict_loading: false

    belongs_to :business, class_name: "::Business", strict_loading: false
    belongs_to :organization, class_name: "::Organization", strict_loading: false
    belongs_to :seat, class_name: "Copilot::Seat", optional: true, strict_loading: false
    # rubocop:todo Rails/InverseOf
    belongs_to :assigned_user, class_name: "::User", foreign_key: :assigned_user_id, strict_loading: false
    # rubocop:enable Rails/InverseOf

    before_validation :copy_organization_to_owner

    scope :for_enterprise, ->(enterprise) { where(business_id: enterprise.id) }
    scope :for_organization, ->(organization) { where(organization_id: organization.id) }
    scope :for_seat, ->(seat) { where(seat_id: seat.id) }
    scope :for_assigned_user, ->(user) { where(assigned_user_id: user.id) }

    sig { void }
    def copy_organization_to_owner
      return if owner.present?
      return unless self.business.present? || self.organization.present?

      self.owner = self.organization || self.business
    end
  end
end
