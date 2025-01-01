# typed: true
# frozen_string_literal: true

class RepositoryLatestRelease < ApplicationRecord::Domain::Repositories
  include ::Repositories::BelongsToRepository
  flagged_belongs_to_repository_via_domain
  belongs_to :release
  validates_presence_of :repository
  validates_presence_of :release

  validate :release_allowed_as_latest
  validate :release_belongs_to_repository

  private

  def release_allowed_as_latest
    return unless release.present?

    rel = T.must(release)
    unless rel.published? && !rel.prerelease?
      errors.add :base, "Latest release cannot be draft or prerelease."
    end
  end

  def release_belongs_to_repository
    return unless release.present? && repository.present?

    unless T.must(release).repository_id == repository_id
      errors.add :base, "Release does not belong to repository."
    end
  end
end
