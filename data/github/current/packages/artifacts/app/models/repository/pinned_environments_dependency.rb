# typed: true
# frozen_string_literal: true

# pinned environments functionality for repositories
module Repository::PinnedEnvironmentsDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { Repository }

  PINNED_ENVIRONMENTS_LIMIT = 10

  included do
    T.bind(self, T.class_of(Repository))
    has_many :pinned_environments,
      -> { order("position ASC") },
      dependent: :destroy
  end

  def can_pin_environments?(user)
    return false unless repository.can_use_environments?
    if user.can_have_granular_permissions?
      resources.environments.writable_by?(user)
    else
      repository.adminable_by?(user)
    end
  end

  # TODO: Expand to use created_at as opposed to getting an array passed in
  def reorder_pinned_environments(ordered_environment_ids)
    pinned_environments.each do |pin|
      position = ordered_environment_ids.index(pin.environment_id) + 1 # 1-based index
      pin.update_attribute(:position, position)
    end
  end
end
