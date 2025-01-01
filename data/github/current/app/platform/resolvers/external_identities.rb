# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class ExternalIdentities < Resolvers::Base
      argument :members_only, Boolean, "Filter to external identities with valid org membership only", required: false
      argument :login, String, "Filter to external identities with the users login", required: false
      argument :user_name, String, "Filter to external identities with the users userName/NameID attribute", required: false

      type Connections.define(Objects::ExternalIdentity), null: false

      def resolve(members_only: false, login: nil, user_name: nil)
        object.async_target.then do |target|
          scope = object.external_identities
          scope = scope.joins(:user).where(user: { login: login }) if login
          scope = scope.where(user_id: target.member_ids) if members_only
          scope = scope.where("user_name = ? OR name_id = ?", user_name, user_name) if user_name
          scope.scoped
        end
      end
    end
  end
end
