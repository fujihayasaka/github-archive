# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class IntegrationSuspensionAction < Platform::Enums::Base
      description "The possible actions to perform on integrations for suspension operations."

      visibility :internal
      map_to_service :spam_checks

      value "SUSPEND", "Suspend the specified integrations.", value: "suspend"
      value "UNSUSPEND", "Unsuspend the specified integrations.", value: "unsuspend"
      value "SUSPEND_ALL_FOR_OWNER", "Suspend all integrations for the specified owner.", value: "suspend_all_for_owner"
      value "UNSUSPEND_ALL_FOR_OWNER", "Unsuspend all integrations for the specified owner.", value: "unsuspend_all_for_owner"
    end
  end
end
