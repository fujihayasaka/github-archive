# typed: true
# frozen_string_literal: true

class Organizations::HeaderNav::RepositoriesTabComponent < ApplicationComponent
  attr_reader :text, :tab_id

  def initialize(organization:, link_classes: nil)
    @organization = organization
    @link_classes = link_classes
    @text = "Repositories"
    @tab_id = "org-header-#{@text.parameterize}-tab"
  end

  memoize def url
    org_repositories_path(@organization)
  end

  def call

    render(Organizations::HeaderNav::TabComponent.new(
      url: url,
      text: text,
      icon: "repo",
      counter_class: "js-profile-repository-count",
      link_classes: @link_classes,
      tab_id: tab_id,
    ))
  end

  memoize def render?
    @organization.present?
  end
end
