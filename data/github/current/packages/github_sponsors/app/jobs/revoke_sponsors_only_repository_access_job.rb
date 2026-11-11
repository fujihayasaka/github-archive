# typed: true
# frozen_string_literal: true

class RevokeSponsorsOnlyRepositoryAccessJob < ApplicationJob
  # This should be in the same queue as GrantSponsorsOnlyRepositoryAccessJob so
  # that there are no race conditions when changing SponsorsTier.repository_id
  # in rapid succession.

  queue_as :sponsors_only_repository_access
  retry_on_dirty_exit

  def perform(sponsor_id, repository_id, sponsors_tier_id)
    return unless GitHub.sponsors_enabled?

    # Make sure the sponsor was granted access to the repository due to a sponsorship:
    sponsorship_repo = SponsorshipRepository.for_tier(sponsors_tier_id).for_repository(repository_id)
      .for_sponsor(sponsor_id).first
    return unless sponsorship_repo

    # If there are more than 1 SponsorshipRepository records for a given sponsor
    # and repository, that means the sponsor is part of multiple tiers that each
    # grant access to the same repository.
    #
    # If that is the case, we should delete the SponsorshipRepository record for
    # the passed in tier (the one they canceled), but should not revoke access
    # to the repo since they are still part of another tier that grants access
    # to the repo.
    if SponsorshipRepository.for_repository(repository_id).for_sponsor(sponsor_id).count > 1
      return with_write { sponsorship_repo.destroy! }
    end

    # Make sure the repo still exists:
    repo = begin
      Repositories::Public.find_active!(repository_id)
    rescue ActiveRecord::RecordNotFound
      return
    end

    sponsor = User.find_by(id: sponsor_id)
    return unless sponsor

    tier = SponsorsTier.find_by(id: sponsors_tier_id)
    return unless tier

    actor = tier.creator || tier.sponsorable
    if repo.readable_by?(sponsor)
      with_write { repo.remove_member(sponsor, actor) }
    end
    success = !repo.readable_by?(sponsor)

    invitation = RepositoryInvitation.for_invitee(sponsor_id).for_repository(repository_id).first
    if success && invitation
      success = with_write { invitation.cancel!(actor: actor, force: true) }
    end

    if success
      with_write { sponsorship_repo.destroy! }
    end
  end
end
