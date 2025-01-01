# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class OrgPendingRepositoryInvitation < Platform::Loader
      include Scientist

      def self.load(org, user_id)
        self.for(org).load(user_id)
      end

      def initialize(org)
        @org = org
      end

      def fetch(user_ids)
        science("org-pending-repository-invitation-loader") do |e|
          e.use { legacy_fetch(user_ids) }
          e.try { batch_fetch(user_ids) }
        end
      end

      def legacy_fetch(user_ids)
        result = {}
        user_ids.each do |user_id|
          result[user_id] = @org.repository_invitations.where(invitee_id: user_id)
        end
        result
      end

      def batch_fetch(user_ids)
        @org.repository_invitations.where(invitee_id: user_ids).each_with_object({}) do |invite, result|
          result[invite.invitee_id] ||= ArrayWrapper.new([])
          result[invite.invitee_id] << invite
        end
      end
    end
  end
end
