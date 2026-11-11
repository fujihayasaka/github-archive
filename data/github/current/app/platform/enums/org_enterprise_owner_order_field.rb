# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class OrgEnterpriseOwnerOrderField < Platform::Enums::Base
      description "Properties by which enterprise owners can be ordered."

      value "LOGIN", "Order enterprise owners by login.", value: "login"
    end
  end
end
