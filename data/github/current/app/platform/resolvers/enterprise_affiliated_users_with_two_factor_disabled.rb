# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class EnterpriseAffiliatedUsersWithTwoFactorDisabled < Resolvers::Base
      type Connections::User, null: false

      def resolve
        ensure_business_not_suspended!(object)

        object.async_organizations.then do
          ArrayWrapper.new(object.affiliated_users_with_two_factor_disabled)
        end
      end
    end
  end
end
