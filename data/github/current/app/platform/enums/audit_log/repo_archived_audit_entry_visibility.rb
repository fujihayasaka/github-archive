# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    module AuditLog
      class RepoArchivedAuditEntryVisibility < Platform::Enums::Base
        description "The privacy of a repository"

        value "INTERNAL", "The repository is visible only to users in the same enterprise.", value: "internal"
        value "PRIVATE", "The repository is visible only to those with explicit access.", value: "private"
        value "PUBLIC", "The repository is visible to everyone.", value: "public"
      end
    end
  end
end
