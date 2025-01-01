# typed: true
# frozen_string_literal: true

# Public: Represents whether a User was granted access to a Repository because
# they're funding a Sponsorable through a SponsorsTier with a sponsors only repo
#
# If a User is funding multiple SponsorsTiers that have the same sponsors only
# repo, the User will have multiple SponsorshipRepository records for the same
# repo, but with different SponsorsTiers. When a User stops funding at a certain
# tier, the SponsorshipRepository record will be deleted for just that tier.
# That way the User has access to the Repository as long as they are funding at
# least one SponsorsTier with that sponsors only repo.
#
# If a User already has access to a Repository that is a sponsors only repo for
# the tier at the time of funding then they will *not* have a
# SponsorshipRepository record created. We did this so that we can track whether
# GitHub Sponsors was the reason for them being granted access, or if they
# already had access before funding a tier. Since we only remove access to a
# sponsors only repo if a SponsorshipRepository record exists for the Sponsor,
# then we would not remove access if they stop funding the tier.
class SponsorshipRepository < ApplicationRecord::Domain::Sponsors
  belongs_to :sponsor, class_name: "User", required: true, inverse_of: :sponsorship_repositories_as_sponsor
  belongs_to :sponsorable, class_name: "User", required: true, inverse_of: :sponsorship_repositories_as_sponsorable
  belongs_to :sponsors_tier, required: true, inverse_of: :sponsorship_repositories
  include ::Repositories::BelongsToRepository
  flagged_belongs_to_repository_via_domain required: true, inverse_of: :sponsorship_repositories

  has_one :sponsorship, ->(sponsorship_repo) {
    T.bind(self, T.untyped)
    unscope(where: :sponsorship_id).with_tier(sponsorship_repo.sponsors_tier_id)
      .from_sponsor(sponsorship_repo.sponsor_id)
      .with_user_or_org_sponsorable(sponsorship_repo.sponsorable_id)
  }, inverse_of: :sponsorship_repository

  scope :for_tier, ->(tier_id) { where(sponsors_tier_id: tier_id) }
  scope :for_repository, ->(repository_id) { where(repository_id: repository_id) }
  scope :for_sponsor, ->(sponsor_id) { where(sponsor_id: sponsor_id) }
  scope :for_sponsorable, ->(sponsorable_id) { where(sponsorable_id: sponsorable_id) }

  validates :sponsors_tier_id, uniqueness: { scope: [:sponsor_id, :repository_id] }
  validate :active_sponsorship_exists_for_sponsor_using_tier
  validate :sponsors_tier_is_for_sponsorable

  # Public: Enqueue a background job to remove the sponsor's access to the repository.
  sig { void }
  def enqueue_revoke_access_job
    RevokeSponsorsOnlyRepositoryAccessJob.perform_later(sponsor_id, repository_id, sponsors_tier_id)
  end

  private

  sig { void }
  def active_sponsorship_exists_for_sponsor_using_tier
    return unless self[:sponsor_id] && sponsorable

    tier = sponsors_tier
    return unless tier

    unless Sponsorship.active.with_tier(sponsors_tier_id).from_sponsor(sponsor_id).exists?
      errors.add(:sponsor, "is not a #{tier.name} sponsor of #{sponsorable}")
    end
  end

  sig { void }
  def sponsors_tier_is_for_sponsorable
    tier = sponsors_tier
    return unless tier && sponsorable

    unless tier.sponsorable == sponsorable
      errors.add(:sponsors_tier, "is not @#{sponsorable}'s")
    end
  end
end
