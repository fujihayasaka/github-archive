# typed: true
# frozen_string_literal: true

module PackageSettings
  class AcceptMarketplaceAgreementComponent < ApplicationComponent
    include TextHelper

    def render?
      return false if !GitHub.marketplace_enabled?
      return false if !FeatureFlag.vexi.enabled_or_raise?(:action_package_marketplace, current_user) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
      true
    end

    def initialize(integrator_agreement:, action:, repository_org_owner:)
      @integrator_agreement = integrator_agreement
      @action = action
      @org_owner = repository_org_owner
    end

    attr_reader :integrator_agreement, :action, :org_owner
  end
end
