# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Models
    module Validity
      class TokenMember
        sig { returns(String) }
        attr_reader :label

        sig { returns(Integer) }
        attr_reader :number

        sig { params(label: String, number: Integer).void }
        def initialize(label:, number:)
          @label = T.let(label, String)
          @number = T.let(number, Integer)
        end

        sig { params(proto: GitHub::Proto::SecretScanning::Api::V2::TokenGroup::TokenMember).returns(TokenMember) }
        def self.from_proto(proto)
          TokenMember.new(
            label: proto.label,
            number: proto.number,
          )
        end
      end
    end
  end
end
