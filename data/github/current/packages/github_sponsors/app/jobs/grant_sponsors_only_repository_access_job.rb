# typed: strict
# frozen_string_literal: true

class GrantSponsorsOnlyRepositoryAccessJob < ApplicationJob
  extend T::Sig

  class FailedToInvite < StandardError; end

  # This should be in the same queue as RevokeSponsorsOnlyRepositoryAccessJob so
  # that there are no race conditions when changing SponsorsTier.repository_id
  # in rapid succession.
  queue_as :sponsors_only_repository_access
  retry_on_dirty_exit

  sig { params(sponsor_id: Integer, repository_id: Integer, sponsors_tier_id: Integer).void }
  def perform(sponsor_id, repository_id, sponsors_tier_id)
    return unless GitHub.sponsors_enabled?

    # Make sure an active repo still exists:
    repo = Repository.find_by(id: repository_id)
    return unless repo&.active?

    sponsor = User.find_by(id: sponsor_id)
    return unless sponsor

    # Make sure the repo is not spammy:
    return if repo.hide_from_user?(sponsor)

    # Make sure the sponsor is not suspended
    return if sponsor.suspended?

    tier = SponsorsTier.find_by(id: sponsors_tier_id)
    return unless tier

    # Make sure this sponsor can be granted access:
    return unless tier.grants_repository_access_to?(sponsor)

    # If there is already a SponsorshipRepository record for this sponsor and
    # repository with another tier, that means the sponsor is part of multiple
    # tiers that each grant access to the same repository.
    #
    # If that is the case, we should create another SponsorshipRepository record
    # for the passed in tier, but can skip the invitation/adding member process
    # since that already should have happened with the previous tier they signed
    # up for.
    if SponsorshipRepository.for_repository(repository_id).for_sponsor(sponsor_id).exists?
      SponsorshipRepository.throttle_writes_with_retry do
        tier.create_sponsorship_repository(sponsor: sponsor)
      end
      return
    end

    return if repo.readable_by?(sponsor) # Nothing to do

    # If the repository is no longer valid for use as a sponsors-only repo, do not invite the sponsor
    return if tier.sponsors_only_repository_errors.any?

    invitation = RepositoryInvitation.for_invitee(sponsor_id).for_repository(repository_id).first

    unless invitation
      actor = tier.actor_for_repository_invitation
      result = RepositoryInvitation.throttle_writes_with_retry do
        RepositoryInvitation.invite_to_repo(sponsor, actor, repo, action: :read, ignore_rate_limit: true)
      end

      raise FailedToInvite.new(result[:errors].messages.values.join(", ")) unless result[:success]

      SponsorshipRepository.throttle_writes_with_retry do
        tier.create_sponsorship_repository(sponsor: sponsor)
      end
    end
  end
end
