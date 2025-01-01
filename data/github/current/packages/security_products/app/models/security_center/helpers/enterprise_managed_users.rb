# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module Helpers
    class EnterpriseManagedUsers
      extend T::Sig
      include GitHub::Memoizer

      sig { returns(::Business) }; attr_reader :business

      sig { params(business: ::Business).void }
      def initialize(business:)
        @business = business
      end

      sig { params(logins: T::Array[String]).returns(T::Array[Integer]) }
      def find_ids(logins:)
        if GitHub.enterprise?
          User
            .where(type: "User")
            .where(login: logins)
            .pluck(:id)
        else
          return [] unless business.enterprise_managed? && business.external_provider.present?
          BusinessUserAccount
            .where(business_id: business.id)
            .where(login: logins)
            .pluck(:user_id)
        end
      end
    end
  end
end
