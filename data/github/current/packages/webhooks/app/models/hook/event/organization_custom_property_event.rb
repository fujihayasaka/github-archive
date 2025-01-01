# typed: true
# frozen_string_literal: true

class Hook::Event::OrganizationCustomPropertyEvent < Hook::Event
  include GitHub::Memoizer

  supports_targets Business

  description "Organization custom property is created, updated, or deleted"

  event_attr :action, :business_id, :definition_id, :property_name, required: true
  event_attr :actor_id

  feature_flag :custom_properties_for_orgs

  memoize def definition
    OrganizationCustomPropertyDefinition.find_by(id: definition_id)
  end

  memoize def actor
    User.find_by(id: actor_id)
  end

  memoize def target_business
    return ::Business.find_by(id: business_id).tap(&:readonly!) if business_id
    super
  end

  # By default feature flag actor is either an org or a repo.
  # Therefore we am providing an override to return the business
  def feature_flag_actor
    target_business
  end
end
