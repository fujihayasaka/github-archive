# typed: strict
# frozen_string_literal: true

module Platform
  module Enums
    class RepositoryLockReason < Platform::Enums::Base
      description "The possible reasons a given repository could be in a locked state."

      value "MOVING", "The repository is locked due to a move.", value: Repository::LockDependency::MOVING
      value "BILLING", "The repository is locked due to a billing related reason.", value: Repository::LockDependency::BILLING
      value "RENAME", "The repository is locked due to a rename.", value: Repository::LockDependency::RENAME
      value "MIGRATING", "The repository is locked due to a migration.", value: Repository::LockDependency::MIGRATING
      value "TRADE_RESTRICTION", "The repository is locked due to a trade controls related reason.", value: Repository::LockDependency::TRADE_RESTRICTION
      value "TRANSFERRING_OWNERSHIP", "The repository is locked due to an ownership transfer.", value: Repository::LockDependency::TRANSFERRING_OWNERSHIP
    end
  end
end
