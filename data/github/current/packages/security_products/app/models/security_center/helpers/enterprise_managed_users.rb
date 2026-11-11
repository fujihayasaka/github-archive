# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module Helpers
    class EnterpriseManagedUsers
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
          if FeatureFlag.vexi.enabled?(:enterprise_primitives_domain_isolation_calls, default: false)
            Admin.domain.business_user_accounts.user_ids_by_business_and_logins(business.id, logins)
          else
            BusinessUserAccount
              .where(business_id: business.id)
              .where(login: logins)
              .pluck(:user_id)
          end
        end
      end
    end
  end
end
