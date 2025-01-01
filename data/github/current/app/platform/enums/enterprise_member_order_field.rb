# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class EnterpriseMemberOrderField < Platform::Enums::Base
      description "Properties by which enterprise member connections can be ordered."

      value "LOGIN", "Order enterprise members by login", value: "login"
      value "CREATED_AT", "Order enterprise members by creation time", value: "created_at"
    end
  end
end
