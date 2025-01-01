# typed: strict
# frozen_string_literal: true

module ScopedInstallations
  module AuthorizationDetails
    class Builder

      sig { params(version: Integer).returns(PublicMethods) }
      def self.build(version: 2)
        case version
        when 1
          Structs::V1.new
        when 2
          Structs::V2.new
        else
          raise ArgumentError, "Unsupported authorization details version: #{version}"
        end
      end

      sig { params(hash: T::Hash[String, T.untyped]).returns(PublicMethods) }
      def self.from_hash(hash)
        case hash["version"]
        when 1
          Structs::V1.from_hash(hash)
        when 2
          Structs::V2.from_hash(hash)
        else
          raise ArgumentError, "Unsupported authorization details version: #{hash["version"]}"
        end
      end
    end
  end
end
