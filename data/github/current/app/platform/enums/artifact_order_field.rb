# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class ArtifactOrderField < Platform::Enums::Base
      description "Properties by which artifact connections can be ordered."
      mobile_only true

      value "CREATED_AT", "Order artifacts by creation time", value: "created_at"
      value "NAME", "Order artifacts alphabetically by name", value: "name"
    end
  end
end
