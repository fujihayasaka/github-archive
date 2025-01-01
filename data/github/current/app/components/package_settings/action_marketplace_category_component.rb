# typed: true
# frozen_string_literal: true

class PackageSettings::ActionMarketplaceCategoryComponent < ApplicationComponent

  def render?
    return false if !GitHub.marketplace_enabled?
    return false if !FeatureFlag.vexi.enabled_or_raise?(:action_package_marketplace, current_user) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
    true
  end

  def initialize(action:)
    @action = action
  end

  attr_reader :action

  memoize def action_primary_category
    return @action_primary_category if defined?(@action_primary_category)

    @action_primary_category = @action&.regular_categories&.first
  end

  memoize def action_secondary_category
    return @action_secondary_category if defined?(@action_secondary_category)

    @action_secondary_category = @action&.regular_categories&.second
  end

  memoize def regular_categories
    @regular_categories ||= ::Marketplace::Category.where(acts_as_filter: false).order(:name)
  end

  memoize def show_security_contact_field?
    action.owned_by_org?
  end

  memoize def security_contact_default_value
    action.security_email
  end
end
