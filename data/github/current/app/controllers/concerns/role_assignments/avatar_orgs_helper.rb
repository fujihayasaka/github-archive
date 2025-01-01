# typed: strict
# frozen_string_literal: true

module RoleAssignments
  module AvatarOrgsHelper
    extend ActiveSupport::Concern
    extend T::Helpers

    include Businesses::Concerns::BusinessAccess

    ENTERPRISE_ORG_AVATAR_LIMIT = 3

    sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def avatar_orgs
      this_business.organizations.
        order(created_at: :desc).
        limit(ENTERPRISE_ORG_AVATAR_LIMIT).
        map do |org|
          { id: org.id, displayLogin: org.display_login, avatarURL: org.primary_avatar_url }
        end
    end
  end
end
