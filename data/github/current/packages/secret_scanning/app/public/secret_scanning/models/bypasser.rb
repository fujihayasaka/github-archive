# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Models
    # Represents a configured bypasser for secret scanning delegated bypass.
    # A bypasser is an entity (user, team, role, etc.) that is authorized to
    # bypass push protection or review bypass requests.
    class Bypasser < T::Struct
      const :id, Integer
      const :owner_id, Integer
      const :owner_scope, T.any(Symbol, Integer)
      const :security_configuration_id, T.nilable(Integer)
      const :reviewer_id, Integer
      const :reviewer_type, T.any(Symbol, Integer)
      const :mode, T.any(Symbol, Integer)

      sig { params(bypasser: GitHub::Proto::SecretScanning::Bypassers::V1::Bypasser).returns(Bypasser) }
      def self.from_proto_bypasser(bypasser)
        Bypasser.new(
          id: bypasser.id,
          owner_id: bypasser.owner_id,
          owner_scope: bypasser.owner_scope,
          security_configuration_id: bypasser.security_configuration_id,
          reviewer_id: bypasser.bypasser_id,
          reviewer_type: bypasser.bypasser_type,
          mode: bypasser.mode,
        )
      end
    end
  end
end
