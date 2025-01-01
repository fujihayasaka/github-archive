# typed: true
# frozen_string_literal: true

class ImmutableActionsOptOut < ApplicationRecord::Ballast
  include Instrumentation::Model
  belongs_to :workflow_repo_owner, class_name: "User"

  validates :workflow_repo_owner_id, presence: true
end
