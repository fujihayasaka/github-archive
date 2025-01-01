# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class EnterpriseServerUserAccountOrderField < Platform::Enums::Base
      description "Properties by which Enterprise Server user account connections can be ordered."

      value "LOGIN", "Order user accounts by login", value: "login"
      value "REMOTE_CREATED_AT", "Order user accounts by creation time on the Enterprise Server installation", value: "remote_created_at"
    end
  end
end
