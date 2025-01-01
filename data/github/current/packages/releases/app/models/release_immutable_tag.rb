# typed: true
# frozen_string_literal: true

class ReleaseImmutableTag < ApplicationRecord::Domain::Repositories
  include ::Repositories::BelongsToRepository
  belongs_to_repository_via_domain
  belongs_to :release

  validates :repository, presence: true
  # We only require a release to be present on creation. The immutable tag record
  # may later be disconnected from the release when the release is destroyed.
  validates :release, presence: true, on: :create
  validates :tag_name, presence: true, uniqueness: { scope: :repository_id }
  validate :release_belongs_to_repository

  private

  def release_belongs_to_repository
    return unless release.present? && repository.present?

    if T.must(release).repository_id != repository_id
      errors.add :base, "Release does not belong to repository."
    end
  end
end
