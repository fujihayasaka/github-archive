# typed: true
# frozen_string_literal: true

class Organizations::HeaderNav::PackagesTabComponent < ApplicationComponent
  attr_reader :text, :tab_id

  def initialize(organization:, link_classes: nil)
    @organization = organization
    @link_classes = link_classes
    @text = "Packages"
    @tab_id = "org-header-#{@text.parameterize}-tab"
  end

  memoize def url
    org_packages_path(@organization)
  end

  def call
    render(Organizations::HeaderNav::TabComponent.new(
      url: url,
      text: text,
      icon: "package",
      link_classes: @link_classes,
      tab_id: tab_id,
    ))
  end

  memoize def render?
    @organization.present? && PackageRegistryHelper.show_packages? && PackageRegistryHelper.allow_access_to_actor?(@organization, current_user)
  end
end
