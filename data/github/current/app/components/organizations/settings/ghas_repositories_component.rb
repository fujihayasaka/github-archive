# typed: true
# frozen_string_literal: true

class Organizations::Settings::GhasRepositoriesComponent < ApplicationComponent

  include SecurityAnalysisSettingsHelper

  def initialize(sku: GitHub::Turboghas::SKU::Bundled, organization:, page_param: 1)
    @organization = organization
    @page_param = page_param.to_i
    @sku = sku
    if @page_param <= 0
      @page_param = 1
    end

    # Note that @organization.advanced_security_license returns the
    # license for the relevant billable entity (org or business), not
    # necessarily for the org on which it's called.
    @advanced_security_license = @organization.advanced_security_license

  end

  def renderer
    case @sku
    when GitHub::Turboghas::SKU::Bundled
      AdvancedSecurityEntitiesLinkRenderer
    when GitHub::Turboghas::SKU::CodeSecurity
      CodeSecurityEntitiesLinkRenderer
    when GitHub::Turboghas::SKU::SecretSecurity
      SecretSecurityEntitiesLinkRenderer
    end
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
end
