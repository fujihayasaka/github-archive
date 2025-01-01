# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    module AuditLog
      class IssueCommentUpdateAuditEntry < Platform::Objects::AuditLog::Base
        description "Audit log entry for a issue.comment_update event."

        visibility :under_development
        minimum_accepted_scopes ["read:user", "admin:org", "admin:enterprise"]


        # Determine whether the viewer can access this object via the API (called internally).
        # This is where Egress checks for OAuth scopes and GitHub Apps go.
        # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
        def self.async_api_can_access?(permission, audit_entry)
          permission.async_api_can_access_audit_entry?(audit_entry)
        end

        # Determine whether the viewer can see this object (called internally).
        # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
        def self.async_viewer_can_see?(permission, audit_entry)
          permission.async_viewer_can_see_audit_entry?(audit_entry)
        end

        implements_node_with_document_id(prefix: "ICUAE")
        implements Platform::Interfaces::AuditLog::AuditEntry
        implements Platform::Interfaces::AuditLog::OrganizationAuditEntryData

        field :body, String, null: true, description: "The issue comment's new body.", deprecated: Helpers::AuditLog::DeprecationNotice
        def body
          @object.get(:body)
        end

        field :body_was, String, null: true, description: "The issue comment's old body.", deprecated: Helpers::AuditLog::DeprecationNotice
        def body_was
          @object.get(:old_body)
        end

        field :issue_comment_database_id, Integer, null: true, visibility: :internal, description: "The issue comment's database ID.", deprecated: Helpers::AuditLog::DeprecationNotice
        def issue_comment_database_id
          @object.get(:issue_comment_id)
        end

        field :issue_comment, Platform::Objects::IssueComment, null: true, description: "The issue comment associated with the Audit Entry.", deprecated: Helpers::AuditLog::DeprecationNotice
        def issue_comment
          Loaders::ActiveRecord.load(::IssueComment, @object.get(:issue_comment_id))
        end

        field :issue_database_id, Integer, null: true, visibility: :internal, description: "The issue's database ID.", deprecated: Helpers::AuditLog::DeprecationNotice
        def issue_database_id
          @object.get(:issue_id)
        end

        field :issue, Platform::Objects::Issue, null: true, description: "The issue associated with the Audit Entry.", deprecated: Helpers::AuditLog::DeprecationNotice
        def issue
          Loaders::ActiveRecord.load(::Issue, @object.get(:issue_id))
        end

        field :is_private_repository, Boolean, null: true, visibility: :internal, description: "Whether the issue's repository was private.", deprecated: Helpers::AuditLog::DeprecationNotice
        def is_private_repository
          @object.get(:private_repo)
        end

        field :is_spammy, Boolean, null: true, visibility: :internal, description: "Whether the issue comment was marked spammy.", deprecated: Helpers::AuditLog::DeprecationNotice
        def is_spammy
          @object.get(:spammy)
        end
      end
    end
  end
end
