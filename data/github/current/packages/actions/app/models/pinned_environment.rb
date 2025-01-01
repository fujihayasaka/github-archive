# typed: false
# frozen_string_literal: true

class PinnedEnvironment < ApplicationRecord::Repositories
  include GitHub::Relay::GlobalIdentification

  belongs_to :repository
  belongs_to :environment
  validates :environment_id, uniqueness: true

  before_create :position_last_on_create

  private

  def position_last_on_create
    max_pos = self.repository.pinned_environments.pluck(:position).max || 0
    self.position = max_pos + 1 # 1-indexed position
  end
end
