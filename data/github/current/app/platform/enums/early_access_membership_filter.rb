# typed: true
# frozen_string_literal: true
module Platform
  module Enums
    class EarlyAccessMembershipFilter < Platform::Enums::Base
      visibility :internal
      description "Condition to filter early access memberships on."

      value "ALL", "All submitted early access requests", value: :all
      value "PENDING", "Early access requests that have not been accepted", value: :pending
      value "ACCEPTED", "Early access requests that have been accepted", value: :accepted
    end
  end
end
