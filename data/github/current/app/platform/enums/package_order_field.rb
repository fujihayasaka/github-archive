# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class PackageOrderField < Platform::Enums::Base
      description "Properties by which package connections can be ordered."

      value "CREATED_AT", "Order packages by creation time", value: "created_at"
    end
  end
end
