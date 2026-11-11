# typed: true
# frozen_string_literal: true

class Hook::Event::OrganizationCustomPropertyValuesEvent < Hook::Event
  include GitHub::Memoizer

  supports_targets Business, Organization, Integration

  description "Custom property values are changed for an organization"

  event_attr :organization_id, :business_id, :new_property_values, :old_property_values, required: true
  event_attr :actor_id

  feature_flag :custom_properties_for_orgs

  memoize def actor
    User.find_by(id: actor_id)
  end

  memoize def target_business
    ::Business.find_by(id: business_id).tap(&:readonly!)
  end

  memoize def target_organization
    Organization.find_by(id: organization_id).tap(&:readonly!)
  end

  def self.visible_for?(user, target)
    return false if target.is_a?(Organization) && target.business.nil?
    super
  end

  # By default feature flag actor is either an org or a repo.
  # Therefore we am providing an override to return the business
  def feature_flag_actor
    target_business
  end
end
