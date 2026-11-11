# typed: strict
# frozen_string_literal: true

module CopilotSpaces
  module AuthorizationHelper
    extend T::Helpers

    sig { params(user: User, cap_filter: ConditionalAccess::Filter).returns(T::Array[Organization]) }
    def self.authorized_orgs(user, cap_filter)
      cap_filter.authorized_resources(user.organizations)
    end
  end
end
