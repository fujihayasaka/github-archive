# typed: true
# frozen_string_literal: true

module Codespaces
  class TrustedRepositoryAuthorization < ApplicationRecord::Domain::UsersCollab
    self.table_name = "gpg_authorizations"

    validate :repository_is_trustable?

    belongs_to :user
    include ::Repositories::BelongsToRepository
    belongs_to_repository_via_domain legacy_return_type: true
    after_create :flush_settings_sync_job

    private

    def flush_settings_sync_job
      CodespacesFlushSettingsSyncJob.perform_later(user: T.must(user))
    end

    def repository_is_trustable?
      return if repository&.readable_by?(user)

      errors.add(:repository, "is not readable by user")
    end
  end
end
