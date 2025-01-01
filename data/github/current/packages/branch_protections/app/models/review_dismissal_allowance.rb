# typed: true
# frozen_string_literal: true

class ReviewDismissalAllowance < ApplicationRecord::Repositories
  include GitHub::Relay::GlobalIdentification

  belongs_to :protected_branch
  belongs_to :actor, polymorphic: true
  validates :protected_branch, presence: true
  validates :actor, presence: true
end
