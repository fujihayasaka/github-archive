# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UnlockPrivateAuditLog < Platform::Mutations::Base
      description "Unlock a private audit log for 1 hour. Will also unlock other private audit logs with the same actor."

      visibility :internal
      minimum_accepted_scopes ["site_admin"]

      argument :audit_log_id, String, "The elasticsearch document id of the audit log to unlock.", required: true
      argument :reason, String, "The reason for unlocking the private audit log.", required: true

      field :unlocked_user_id, ID, "The global relay id of the actor who's private audit logs were unlocked.", null: true

      def resolve(audit_log_id:, reason:)
        unless self.class.viewer_is_site_admin?(context[:viewer], self.class.name)
          raise Errors::Forbidden.new("#{context[:viewer].display_login} does not have permission to unlock private audit logs.")
        end

        audit_log = find_audit_log(id: audit_log_id)
        raise Errors::NotFound.new("No audit log with id '#{audit_log_id}' found") unless audit_log.present?

        Loaders::ActiveRecord.load(::User, audit_log[:actor_id], security_violation_behaviour: :nil).then do |actor|
          raise Errors::NotFound.new("No user with id '#{audit_log[:actor_id]}' found") unless actor.present?
          context[:viewer].unlock_private_audit_logs_for(actor, reason: reason)
          { unlocked_user_id: actor.global_relay_id }
        end
      end

      private

      def find_audit_log(id:)
        Audit::load_from_global_id(id)
      end
    end
  end
end
