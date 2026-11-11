# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class SdnActor < Platform::Enums::Base
      description "Specially Designated Nationals (SDN) possible actor types."
      visibility :internal, environments: [:dotcom]

      value "USER", "Indicates a user actor.", value: "user"
      value "ORGANIZATION", "Indicates an organization actor.", value: "organization"
      value "ENTERPRISE", "Indicates an enterprise actor.", value: "enterprise"
    end
  end
end
