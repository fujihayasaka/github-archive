# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class EnterpriseManagedTypeValue < Platform::Enums::Base

      # These values map to the :business_type enum on the Business model.
      description "The possible values for the enterprise managed type."

      value "DEFAULT_MANAGED", "The default managed type for an enterprise."
      value "ENTERPRISE_MANAGED", "Enterprise has enterprise managed user provisioning enabled"
    end
  end
end
