# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class PackageFileOrderField < Platform::Enums::Base
      description "Properties by which package file connections can be ordered."

      value "CREATED_AT", "Order package files by creation time", value: "created_at"
    end
  end
end
