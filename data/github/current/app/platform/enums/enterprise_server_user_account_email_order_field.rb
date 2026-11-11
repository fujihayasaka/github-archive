# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class EnterpriseServerUserAccountEmailOrderField < Platform::Enums::Base
      description "Properties by which Enterprise Server user account email connections can be ordered."

      value "EMAIL", "Order emails by email", value: "email"
    end
  end
end
