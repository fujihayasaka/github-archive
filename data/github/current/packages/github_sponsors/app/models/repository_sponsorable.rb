# typed: true
# frozen_string_literal: true

class RepositorySponsorable < ApplicationRecord::Domain::Repositories
  belongs_to :repository, required: true
  belongs_to :sponsorable, required: true, class_name: :User

  enum :source, {
    owner: 0,
    repo_funding_file: 1,
    global_funding_file: 2,
  }

  # Public: Whether a validation should ensure the repository is not already associated with the sponsorable from
  # its particular source.
  attr_accessor :skip_uniqueness_check

  # Public: Whether a validation should ensure that the sponsorable has a public GitHub Sponsors profile.
  attr_accessor :skip_sponsorable_can_be_sponsored_check

  validates :sponsorable_id, uniqueness: { scope: [:repository_id, :source] }, unless: :skip_uniqueness_check
  validates :source, inclusion: { in: sources.keys }
  validate :repository_owned_by_sponsorable, if: :owner?
  validate :repository_has_funding_file, if: :repo_funding_file?
  validate :repository_has_global_funding_file, if: :global_funding_file?
  validate :sponsorable_can_be_sponsored, unless: :skip_sponsorable_can_be_sponsored_check

  scope :with_source, ->(source) { where(source: source) }
  scope :for_repository, ->(repo_ids) { where(repository_id: repo_ids) }
  scope :not_for_repository, ->(repo_ids) { where.not(repository_id: repo_ids) }
  scope :for_sponsorable, ->(sponsorable_ids) { where(sponsorable_id: sponsorable_ids) }
  scope :not_for_sponsorable, ->(sponsorable_ids) { where.not(sponsorable_id: sponsorable_ids) }

  private

  def repository_owned_by_sponsorable
    return unless repository
    repo = T.must(repository)
    unless repo.owner_id == sponsorable_id
      errors.add(:sponsorable, "must be the owner of repository #{repo.nwo}")
    end
  end

  def repository_has_funding_file
    return unless repository

    # We can trust `repository_preferred_files` on dotcom because it has been backfilled, and we don't need to
    # worry about Enterprise because GitHub Sponsors isn't enabled there:
    unless T.must(repository).repository_preferred_files.funding.any?
      errors.add(:repository, "must have a funding.yml")
    end
  end

  def repository_has_global_funding_file
    return unless repository
    unless T.must(repository).preferred_files.exists?(:funding, global: true)
      errors.add(:repository, "must have a global funding.yml")
    end
  end

  def sponsorable_can_be_sponsored
    return unless sponsorable
    unless T.must(sponsorable).approved_sponsors_listing
      errors.add(:sponsorable, "must have a published GitHub Sponsors profile")
    end
  end
end
