# frozen_string_literal: true

# Defines access to repositories other than the target of an update
class RepositoryAccess < ApplicationRecord
  belongs_to :account

  validates :account, presence: true
  validates :github_id, presence: true
end
