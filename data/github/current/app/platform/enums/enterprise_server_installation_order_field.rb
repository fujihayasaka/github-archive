# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class EnterpriseServerInstallationOrderField < Platform::Enums::Base
      description "Properties by which Enterprise Server installation connections can be ordered."

      value "HOST_NAME", "Order Enterprise Server installations by host name", value: "host_name"
      value "CUSTOMER_NAME", "Order Enterprise Server installations by customer name", value: "customer_name"
      value "CREATED_AT", "Order Enterprise Server installations by creation time", value: "created_at"
    end
  end
end
