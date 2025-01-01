# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    module AuditLog
      class OrgRestoreMemberAuditEntryMembership < Platform::Unions::Base
        description "Types of memberships that can be restored for an Organization member."

        def self.resolve_type(object, context)
          case
          when object.key?("org")
            Objects::AuditLog::OrgRestoreMemberMembershipOrganizationAuditEntryData
          when object.key?("repo")
            Objects::AuditLog::OrgRestoreMemberMembershipRepositoryAuditEntryData
          when object.key?("team")
            Objects::AuditLog::OrgRestoreMemberMembershipTeamAuditEntryData
          end
        end

        possible_types(
          Platform::Objects::AuditLog::OrgRestoreMemberMembershipOrganizationAuditEntryData,
          Platform::Objects::AuditLog::OrgRestoreMemberMembershipRepositoryAuditEntryData,
          Platform::Objects::AuditLog::OrgRestoreMemberMembershipTeamAuditEntryData,
        )
      end
    end
  end
end
