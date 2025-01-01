# typed: false
# frozen_string_literal: true

module Platform
  module Resolvers
    class ObfuscatedDuplicateEmails < Resolvers::Base

      type Connections.define(Objects::UserEmail), null: false

      argument :skip_spammy, Boolean, "Do not include emails for spammy users.", required: false

      def resolve(skip_spammy: nil)
        skip_spammy = !!skip_spammy
        relation = UserEmail.none
        user = object.account
        return relation unless user.is_a?(User)

        user.async_primary_user_email.then do |user_email|
          if user_email.present?
            pattern = UserEmail.deobfuscate user_email.email
            relation = UserEmail.where(deobfuscated_email: pattern).where("user_id <> ?", user.id)
            relation = relation.not_spammy if skip_spammy
            relation
          else
            relation
          end
        end
      end
    end
  end
end
