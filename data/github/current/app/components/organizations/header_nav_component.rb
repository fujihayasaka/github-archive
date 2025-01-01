# typed: true
# frozen_string_literal: true

class Organizations::HeaderNavComponent < ApplicationComponent
  include GlobalNavigationHelper
  include ResilienceHelper

  def initialize(organization:, selected_nav_item:)
    @organization = organization
    unless valid_nav_item?(selected_nav_item)
      raise "Selected nav item (#{selected_nav_item.inspect}) is invalid. Valid ones are " \
        "#{Orgs::HeaderView::VALID_NAV_ITEMS.inspect}."
    end
    @selected_nav_item = selected_nav_item
  end

  private

  attr_reader :organization, :selected_nav_item

  def render?
    # This component is not shown in the new global nav,
    # and this component will likely be deleted along with other legacy views for the old header
    # once the header_redesign_enabled? helper is removed.
    # We will keep this around for now because the legacy header is still enabled on some pages.
    return false if header_redesign_enabled?
    organization.present?
  end

  memoize def link_components
    [
      Organizations::HeaderNav::OverviewTabComponent.new(
        organization: organization,
        link_classes: selected_class_for_nav_item(:overview),
      ),
      Organizations::HeaderNav::RepositoriesTabComponent.new(
        organization: organization,
        link_classes: selected_class_for_nav_item(:repos),
      ),
      Organizations::HeaderNav::DiscussionsTabComponent.new(
        organization: organization,
        link_classes: selected_class_for_nav_item(:discussions),
      ),
      Organizations::HeaderNav::ProjectsTabComponent.new(
        organization: organization,
        link_classes: selected_class_for_nav_item(:projects),
      ),
      Organizations::HeaderNav::PackagesTabComponent.new(
        organization: organization,
        link_classes: selected_class_for_nav_item(:packages),
      ),
      Organizations::HeaderNav::TeamsTabComponent.new(
        organization: organization,
        link_classes: selected_class_for_nav_item(:teams),
        is_direct_or_team_member: direct_or_team_member?,
      ),
      Organizations::HeaderNav::PeopleTabComponent.new(
        organization: organization,
        link_classes: selected_class_for_nav_item(:members),
        is_billing_manager: billing_manager?,
        is_direct_or_team_member: direct_or_team_member?,
      ),
      Organizations::HeaderNav::SecurityTabComponent.new(
        organization: organization,
        link_classes: selected_class_for_nav_item(:security_center),
        is_org_member: direct_or_team_member?,
      ),
      Organizations::HeaderNav::InsightsTabComponent.new(
        organization: organization,
        link_classes: selected_class_for_nav_item(:insights),
        is_org_member: direct_or_team_member?,
      ),
      Organizations::HeaderNav::SponsoringTabComponent.new(
        organization: organization,
        link_classes: selected_class_for_nav_item(:sponsoring),
        is_billing_manager: billing_manager?,
        is_org_member: direct_or_team_member?,
      ),
      Organizations::HeaderNav::SettingsTabComponent.new(
        organization: organization,
        link_classes: selected_class_for_nav_item(:settings),
        setting_fgps: setting_fgps,
      ),
    ]
  end

  # Private: Get links to include in the responsive kebab '...' menu. Only links that are also shown
  # in the non-kebab menu will be included.
  #
  # Returns an Array of ApplicationComponent, each of which should respond to #url, #text, and
  # #tab_id.
  def responsive_menu_link_components
    link_components.select do |comp|
      with_database_error_fallback(fallback: false) do
        comp.render?
      end
    end
  end

  def container_xl?
    view_context.container_xl? || overview?
  end

  def mobile?
    helpers.mobile?
  end

  def overview?
    selected_nav_item == :overview
  end

  memoize def setting_fgps
    organization.org_settings_permissions_hash(current_user)
  end

  # Private: Is the current user a billing_manager of the current
  # organization. Memoized to prevent repeat database roundtrips.
  #
  # Returns a Boolean.
  memoize def billing_manager?
    setting_fgps[:is_billing_manager]
  end

  # Private: Is the current user a direct or team member of the current
  # organization. Memoized to prevent database roundtrips.
  #
  # Returns a Boolean.
  memoize def direct_or_team_member?
    organization.direct_or_team_member?(current_user, include_indirect_abilities: true)
  end

  # Private: Get the CSS class to use for showing the selected state of the specified nav item.
  #
  # nav_item - Name of nav item to get the CSS class for.
  #
  # Returns a string.
  def selected_class_for_nav_item(nav_item)
    unless valid_nav_item?(nav_item)
      raise "Passed nav item (#{nav_item}) is invalid. Valid ones are " \
        "#{Orgs::HeaderView::VALID_NAV_ITEMS.inspect}."
    end

    "selected" if nav_item == selected_nav_item
  end

  # Private: Is the specified nav item valid?
  #
  # nav_item - Name of nav item to check validity of.
  #
  # Returns a boolean.
  def valid_nav_item?(nav_item)
    Orgs::HeaderView::VALID_NAV_ITEMS.include?(nav_item)
  end
end
