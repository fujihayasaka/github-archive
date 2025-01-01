# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class OrganizationOrderField < Platform::Enums::Base
      description "Properties by which organization connections can be ordered."

      value "CREATED_AT", "Order organizations by creation time", value: "created_at"
      value "LOGIN", "Order organizations by login", value: "login"
    end
  end
end
