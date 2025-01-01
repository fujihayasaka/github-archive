# typed: true
# frozen_string_literal: true

# Track contributions made to repositories that were archived in the Arctic Code Vault (ACV)
class AcvContributor < ApplicationRecord::Collab


  belongs_to :repository

  validates :contributor_email, uniqueness: {
    scope: :repository,
    case_sensitive: false
  }

  scope :group_by_repository, ->(emails) {
    where(ignore: false, contributor_email: emails).group(:repository_id)
  }

  scope :includes_ignored, ->(emails) {
    where(contributor_email: emails)
  }

end
