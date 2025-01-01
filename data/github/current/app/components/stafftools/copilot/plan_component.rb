# typed: strict
# frozen_string_literal: true

class Stafftools::Copilot::PlanComponent < ApplicationComponent
  extend T::Sig

  sig { returns(T.any(Copilot::Organization, Copilot::Business)) }
  attr_reader :copilot_entity

  sig { params(copilot_entity: T.any(Copilot::Organization, Copilot::Business)).void }
  def initialize(copilot_entity)
    @copilot_entity = copilot_entity
  end

  sig { returns(String) }
  def current_copilot_plan
    copilot_entity.copilot_plan
  end

  sig { returns(String) }
  def candidate_copilot_plan
    if copilot_entity.copilot_plan_business?
      "enterprise"
    else
      "business"
    end
  end

  sig { returns(T::Boolean) }
  memoize def copilot_mixed_licenses_enabled?
    return entity_object.feature_enabled?(:copilot_mixed_licenses) if business?

    organization = T.cast(entity_object, ::Organization)
    return false unless organization.business.present?

    T.must(organization.business).feature_enabled?(:copilot_mixed_licenses)
  end

  sig { returns(T::Boolean) }
  def can_update_copilot_plan?
    return false if standalone_business?
    return false if entity_object.is_a?(::Business) && copilot_mixed_licenses_enabled?
    return false if entity_object.is_a?(::Organization) && !T.cast(entity_object, Organization).business.present?

    true
  end

  sig { returns(String) }
  memoize def update_copilot_plan_path
    if business?
      business_update_copilot_plan_stafftools_enterprise_path(copilot_entity)
    else
      stafftools_user_copilot_update_plan_path(copilot_entity)
    end
  end

  private

  sig { returns(T.any(::Organization, ::Business)) }
  memoize def entity_object
    copilot_entity.__getobj__
  end

  sig { returns(T::Boolean) }
  memoize def organization?
    entity_object.is_a?(::Organization)
  end

  sig { returns(T::Boolean) }
  memoize def business?
    entity_object.is_a?(::Business)
  end

  sig { returns(T::Boolean) }
  memoize def standalone_business?
    return false unless business?
    T.cast(copilot_entity, Copilot::Business).copilot_standalone?
  end
end
