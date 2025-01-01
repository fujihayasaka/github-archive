# typed: false
# frozen_string_literal: true

class PinnedEnvironment < ApplicationRecord::ActionsEnvironments
  include GitHub::Relay::GlobalIdentification

  include ::Repositories::BelongsToRepository
  belongs_to_repository_via_domain return_type: T.nilable(Repositories::IRepository)
  belongs_to :environment
  validates :environment_id, uniqueness: true

  before_create :position_last_on_create

  private

  def position_last_on_create
    max_pos = self.repository.pinned_environments.pluck(:position).max || 0
    self.position = max_pos + 1 # 1-indexed position
  end
end
