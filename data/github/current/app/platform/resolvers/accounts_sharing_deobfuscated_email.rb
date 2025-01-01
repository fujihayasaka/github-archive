# typed: false
# frozen_string_literal: true

module Platform
  module Resolvers
    class AccountsSharingDeobfuscatedEmail < Resolvers::Base

      type Connections.define(Unions::Account), null: false

      argument :include_main_account, Boolean, "Include the account that this is nested within.", required: false, default_value: false
      argument :include_spammy, Boolean, "Include spammy users.", required: false, default_value: false

      def resolve(include_main_account: false, include_spammy: false)
        relation = User.none
        user = object.account
        return relation unless user.is_a?(User)

        user.async_primary_user_email.then do |user_email|
          if user_email.present?
            pattern = UserEmail.deobfuscate(user_email.email)
            user_ids = UserEmail.where("user_emails.deobfuscated_email": pattern).pluck(:user_id)
            user_ids -= [user.id] unless include_main_account
            relation = User.where(id: user_ids)
            relation = relation.not_spammy unless include_spammy
            relation
          else
            relation
          end
        end
      end
    end
  end
end
