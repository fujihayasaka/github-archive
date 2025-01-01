# typed: false
# frozen_string_literal: true

# Track contributions made to repositories for a profile highlight
class ProfileHighlightContribution < ApplicationRecord::Collab
  belongs_to :profile_highlight
  belongs_to :repository

  after_commit :update_profile_highlight_eligibility, if: :saved_change_to_ignore?

  # ProfileHighlightContributions are static
  # Contributions are attributed to a User based on verified email when the contribution record is created
  # but future changes to a user's verified emails will not change the contributions shown,
  # contributor_email was included in the record in case there are changes in the behavior in the near future
  # or to aid in debugging.
  validates :contributor_email, uniqueness: { scope: [:profile_highlight, :repository] }

  scope :group_by_repository, -> {
    where(ignore: false).group(:repository_id)
  }

  def update_profile_highlight_eligibility
    eligible_contribution_count = profile_highlight.profile_highlight_contributions.where(ignore: false).count
    if eligible_contribution_count > 0
      return if profile_highlight.eligible?
      profile_highlight.update_attribute(:eligible, true)
    else
      return unless profile_highlight.eligible?
      profile_highlight.update_attribute(:eligible, false)
    end
  end
end
