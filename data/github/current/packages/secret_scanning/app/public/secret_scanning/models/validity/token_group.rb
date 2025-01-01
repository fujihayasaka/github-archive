# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Models
    module Validity
      class TokenGroup
        extend T::Sig

        sig { returns(T.nilable(Time)) }
        attr_reader :validity_last_checked

        sig { returns(T.any(Symbol, Integer)) }
        attr_reader :validity

        sig { returns(T::Array[TokenMember]) }
        attr_reader :members

        sig { params(members: T::Array[TokenMember], validity: T.any(Symbol, Integer), validity_last_checked: T.nilable(Time)).void }
        def initialize(members:, validity:, validity_last_checked:)
          @members = T.let(members, T::Array[TokenMember])
          @validity = validity
          @validity_last_checked = validity_last_checked
        end

        sig { params(proto: GitHub::Proto::SecretScanning::Api::V2::TokenGroup).returns(TokenGroup) }
        def self.from_proto(proto)
          TokenGroup.new(
            members: proto.members.to_a.map { |member| TokenMember.from_proto(member) },
            validity: proto.validity,
            validity_last_checked: proto.validation_details&.validity_last_checked&.to_time,
          )
        end
      end
    end
  end
end
