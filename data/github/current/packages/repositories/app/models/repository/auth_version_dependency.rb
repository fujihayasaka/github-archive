# typed: strict
# frozen_string_literal: true

module Repository::AuthVersionDependency
  extend T::Helpers
  extend T::Sig
  extend ActiveSupport::Concern

  requires_ancestor { Repository }

  included do
    T.bind(self, T.class_of(Repository))

    has_one :repository_auth_version, dependent: :destroy
  end

  # Public: Return this repository's current auth version.
  #
  # For repositories that have never changed metadata that affects which users have access to
  # view it, the auth version will default to 1.
  #
  # For repositories that have changed this metadata after creation, the version number will
  # increment for each such change.
  #
  # Returns the Integer version number.
  sig { returns(Integer) }
  def auth_version
    repository_auth_version&.version || 1
  end

  # Public: Return this repository's Blackbird sequence number (i.e. repo_seq_no).
  #
  # For repositories that have changed Blackbird-tracked metadata after creation, the version number will
  # increment for each such change.
  alias blackbird_seq_no auth_version

  # Public: Increment the auth version for this repository.
  #
  # Create or update/increment the repository's associated auth version.
  #
  # Returns the Integer version number.
  sig { returns(Integer) }
  def increment_auth_version
    ApplicationRecord::Domain::Repositories.connection.insert(Arel.sql(<<-SQL, repository_id: self.id, version: 2))
      INSERT INTO repository_auth_versions (repository_id, version, created_at, updated_at)
      VALUES (:repository_id, :version, NOW(), NOW())
      ON DUPLICATE KEY UPDATE
        version = version + 1,
        updated_at = NOW()
    SQL

    # Reset the association to ensure we load the most recent version from the DB
    T.unsafe(self).reset_repository_auth_version
    auth_version
  end
end
