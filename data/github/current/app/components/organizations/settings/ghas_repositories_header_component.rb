# typed: true
# frozen_string_literal: true

class Organizations::Settings::GhasRepositoriesHeaderComponent < ApplicationComponent

  include SecurityAnalysisSettingsHelper

  def initialize(sku: GitHub::Turboghas::SKU::Bundled, organization:)
    @organization = organization
    @sku = sku
  end

  def render?
    case @sku
    when GitHub::Turboghas::SKU::Bundled
      @organization.advanced_security_purchased?
    when GitHub::Turboghas::SKU::CodeSecurity
      @organization.code_security_purchased?
    when GitHub::Turboghas::SKU::SecretSecurity
      @organization.secret_protection_purchased?
    end
  end

  # Note that @organization.advanced_security_license returns the
  # license for the relevant billable entity (org or business), not
  # necessarily for the org on which it's called.
  memoize def advanced_security_license
    @organization.advanced_security_license
  end

  memoize def code_security
    @organization.code_security
  end

  memoize def secret_protection
    @organization.secret_protection
  end

  memoize def advanced_security_purchased?
    @organization.advanced_security_purchased?
  end

  # This includes committers who may also be active in other orgs
  memoize def seats_used_by_org
    @organization.advanced_security_seats_used(sku: @sku)
  end

  memoize def unused_seats
    [0, purchased_seats - consumed_seats].max
  end

  memoize def purchased_seats
    case @sku
    when GitHub::Turboghas::SKU::Bundled
      advanced_security_license.seats
    when GitHub::Turboghas::SKU::CodeSecurity
      code_security.seats
    when GitHub::Turboghas::SKU::SecretSecurity
      secret_protection.seats
    end
  end

  memoize def consumed_seats
    case @sku
    when GitHub::Turboghas::SKU::Bundled
      advanced_security_license.consumed_seats
    when GitHub::Turboghas::SKU::CodeSecurity
      code_security.seats_used
    when GitHub::Turboghas::SKU::SecretSecurity
      secret_protection.seats_used
    end
  end

  memoize def other_entities_licenses
    consumed_seats - seats_used_by_org
  end

  memoize def unlimited_seats?
    case @sku
    when GitHub::Turboghas::SKU::Bundled
      advanced_security_license.unlimited_seats?
    when GitHub::Turboghas::SKU::CodeSecurity
      code_security.unlimited_seats?
    when GitHub::Turboghas::SKU::SecretSecurity
      secret_protection.unlimited_seats?
    end
  end

  memoize def business_license?
    case @sku
    when GitHub::Turboghas::SKU::Bundled
      advanced_security_license.billable_entity.is_a?(Business)
    when GitHub::Turboghas::SKU::CodeSecurity
      code_security.billable_entity.is_a?(Business)
    when GitHub::Turboghas::SKU::SecretSecurity
      secret_protection.billable_entity.is_a?(Business)
    end
  end
end
