# typed: true
# frozen_string_literal: true

module SecurityProductsEnablement
  class RepositoryCodeSecurityPolicyNotificationComponent < ApplicationComponent
    TEST_SELECTOR = "security-analysis-policy-notification"
    attr_reader :blocked_by, :system_arguments

    def initialize(blocked_by, **system_arguments)
      @blocked_by = blocked_by
      @system_arguments = system_arguments
    end

    private

    def organization?
      blocked_by.is_a?(::Organization)
    end
  end
end
