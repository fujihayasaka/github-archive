# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class PackageVersionOrderField < Platform::Enums::Base
      description "Properties by which package version connections can be ordered."

      value "CREATED_AT", "Order package versions by creation time", value: "created_at"
    end
  end
end
