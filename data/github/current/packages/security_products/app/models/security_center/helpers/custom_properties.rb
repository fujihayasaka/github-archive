# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module Helpers
    class CustomProperties
      include GitHub::Memoizer

      sig { returns(::Organization) }; attr_reader :org
      sig { returns(::User) }; attr_reader :user

      sig { params(org: ::Organization, user: ::User).void }
      def initialize(org:, user:)
        @org = org
        @user = user
      end

      sig { returns(T::Array[T::Hash[Symbol, String]]) }
      memoize def definitions_for_frontend
        Repositories.domain.custom_properties.get_definitions(org).map do |definition|
          {
            name: definition.property_name,
            type: definition.value_type
          }
        end
      end
    end
  end
end
