# typed: true
# frozen_string_literal: true

class Hook::Event::CustomPropertyValuesEvent < Hook::Event
  include GitHub::Memoizer

  supports_targets Organization, Repository, Integration

  description "Custom property values are changed for a repository"

  event_attr :organization_id, :repository_id, :new_property_values, :old_property_values, required: true
  event_attr :actor_id

  memoize def actor
    User.find_by(id: actor_id)
  end

  memoize def target_repository
    Repositories.domain.by_id(repository_id).tap(&:readonly!)
  end

  memoize def target_organization
    Organization.find_by(id: organization_id).tap(&:readonly!)
  end

  def self.visible_for?(user, target)
    return target.owner.class == Organization if target.class == Repository

    true
  end
end
