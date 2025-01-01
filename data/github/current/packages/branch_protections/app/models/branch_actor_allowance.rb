# typed: true
# frozen_string_literal: true

class BranchActorAllowance < ApplicationRecord::Domain::Repositories
  include GitHub::Relay::GlobalIdentification

  belongs_to :protected_branch
  belongs_to :actor, polymorphic: true
  validates :protected_branch, presence: true
  validates :actor, presence: true

  TYPES = {
    pull_request: 0,
    force_push: 1
  }.with_indifferent_access.freeze

  enum :policy, TYPES, prefix: true
end
