# typed: strict
# frozen_string_literal: true

module Platform
  module Unions
    class SdnSuspendable < Platform::Unions::Base
      description "Possible actor types that can be SDN (Specially Designated Nationals) suspendable."

      visibility :internal, environments: [:dotcom]

      possible_types(
        Objects::User,
        Objects::Organization,
        Objects::Enterprise
      )
    end
  end
end
