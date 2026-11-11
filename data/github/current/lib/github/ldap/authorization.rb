# typed: true
# frozen_string_literal: true

module GitHub
  module LDAP
    # Authorization is a value object encapsulating whether a Net::LDAP::Entry
    # has access. It includes information about how access was granted or
    # denied.
    class Authorization
      VALID_STATES = [:valid, :valid_membership, :valid_user_account_control]
      INVALID_STATES = [:invalid_membership, :invalid_user_account_control]

      attr_reader :state

      def initialize(state)
        @state = state
      end

      def valid?
        VALID_STATES.include?(state)
      end
    end
  end
end
