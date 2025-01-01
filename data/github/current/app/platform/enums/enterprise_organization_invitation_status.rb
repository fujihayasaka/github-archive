# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class EnterpriseOrganizationInvitationStatus < Platform::Enums::Base
      visibility :under_development
      description "The possible statuses of an enterprise organization invitation."

      value "CREATED",   "An invitation created by an enterprise administrator, not yet accepted.", value: :created
      value "ACCEPTED",  "An invitation accepted by the organization administration, not yet confirmed.", value: :accepted
      value "CONFIRMED", "An invitation confirmed by an enterprise administrator, meaning the organization became part of the enterprise.", value: :confirmed
      value "CANCELED",  "An invitation declined by either the enterprise administrator or the organization administrator, meaning the organization did not become part of the enterprise.", value: :canceled
      value "COMPLETED", "An invitation has been processed and marked as completed by GitHub sales operations.", value: :completed
    end
  end
end
