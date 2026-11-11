# typed: true
# frozen_string_literal: true

module Configurable
  module SecurityConfigurations
    extend T::Helpers

    requires_ancestor { Organization }

    # This feature is available to Organizations but isn't available to Users.
    sig { returns(T::Boolean) }
    def security_configurations_enabled?
      true
    end
  end
end
