# typed: true
# frozen_string_literal: true

class Hook::Event::CustomPropertyEvent < Hook::Event
  include GitHub::Memoizer

  supports_targets Business, Organization, Integration

  description "Custom property is created, updated, deleted, or promoted."

  event_attr :action, :definition_id, :property_name, required: true
  event_attr :actor_id, :org_id, :business_id

  memoize def definition
    CustomPropertyDefinition.find_by(id: definition_id)
  end

  memoize def actor
    User.find_by(id: actor_id)
  end

  memoize def target_organization
    Organization.find_by(id: org_id).tap(&:readonly!) if org_id
  end

  memoize def target_business
    if business_id
      ::Business.find_by(id: business_id).tap(&:readonly!)
    else
      super
    end
  end
end
