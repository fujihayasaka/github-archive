# typed: strict
# frozen_string_literal: true

module CopilotSpaces
  module AuthorizationHelper
    extend T::Helpers

    sig { params(user: User, cap_filter: ConditionalAccess::Filter).returns(T::Array[Organization]) }
    def self.authorized_orgs_with_copilot_access(user, cap_filter)
      orgs = cap_filter.authorized_resources(user.organizations)
      orgs.select { |org| Copilot::Organization.new(org).copilot_enabled? }
    end
  end
end
