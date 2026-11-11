# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class ArtifactOrderField < Platform::Enums::Base
      description "Properties by which artifact connections can be ordered."
      required_capabilities [:mobile_only_schema_mask]

      value "CREATED_AT", "Order artifacts by creation time", value: "created_at"
      value "NAME", "Order artifacts alphabetically by name", value: "name"
    end
  end
end
