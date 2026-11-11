# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class PackagesErrorType < Platform::Enums::Base
      description "Classes of errors that may occur when executing a GitHub Packages mutation."

      visibility :internal

      value "NONE", "The request was successful.", value: "none"
      value "FEATURE_FLAG", "The packages owning account is not opted into a necessary feature flag.", value: "feature_flag"
      value "PLAN_INELIGIBLE", "The packages owning account is on a legacy plan and can't use the service.", value: "plan_ineligible"
      value "RESOURCE_LIMITED", "The packages owning account has exceeded its storage or bandwidth allotment.", value: "resource_limited"
      value "ACCOUNT_DISABLED", "The packages owning account has been disabled due to billing, spam status, or otherwise.", value: "account_disabled"
      value "TRADE_RESTRICTION", "The packages owning account has trade restrictions in place.", value: "trade_restriction"
      value "USER_BLOCKED", "The current user has been blocked by the packages owner.", value: "user_blocked"
      value "USER_SPAMMY", "The current user is spammy and should not interact with packages.", value: "user_spammy"
      value "REPOSITORY_LOCKED", "The repository is locked for billing, migration, renames, etc., and can't accept uploads.", value: "repository_locked"
      value "REPOSITORY_DISABLED", "The repository is disabled for billing, by a GitHub admin, for a ToS violation, DMCA notice, or other, and can't accept uploads.", value: "repository_disabled"
      value "REPOSITORY_ARCHIVED", "The repository is archived and can't accept uploads.", value: "repository_archived"
      value "REPOSITORY_SPAMMY", "The repository or its owner is spammy and it can't accept uploads.", value: "repository_spammy"
      value "WRONG_REPOSITORY", "An attempt to associate a package with a repository other than its current one.", value: "wrong_repository"
      value "PACKAGE_EXISTS", "An attempt to publish a package that already exists.", value: "package_exists"
      value "VERSION_EXISTS", "An attempt to publish a package version that already exists.", value: "version_exists"
      value "FILE_EXISTS", "An attempt to add a package file that already exists on a given version.", value: "file_exists"
      value "VALIDATION", "One or more general validation errors.", value: "validation"
      value "BILLING_VNEXT_BLOCKED", "The request was blocked by the billing vnext platform.", value: "billing_error"
    end
  end
end
