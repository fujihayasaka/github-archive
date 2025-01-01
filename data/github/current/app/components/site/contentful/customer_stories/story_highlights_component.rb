# typed: true
# frozen_string_literal: true

class Site::Contentful::CustomerStories::StoryHighlightsComponent < ApplicationComponent
  include UrlHelper

  PRODUCTS = Site::Contentful::CustomerStories::CustomerStory::ORDERED_STORY_PRODUCTS

  def initialize(highlights: [], classes: nil, dark: false, large_names: false, products: [], icon_size: :small)
    @highlights = highlights
    @classes = classes
    @dark = dark
    @large_names = large_names
    @icon_size = icon_size
    @products = products
    @product_paths = []
  end

  def before_render
    @product_paths = self.product_paths
  end

  def product_paths
    {
      PRODUCTS[:ENTERPRISE] => enterprise_marketing_page_path,
      PRODUCTS[:TEAM] => team_marketing_page_path,
      PRODUCTS[:ACTIONS] => features_actions_path,
      PRODUCTS[:CODESPACES] => features_codespaces_path,
      PRODUCTS[:COPILOT] => features_copilot_path,
      PRODUCTS[:DISCUSSIONS] => features_discussions_path,
      PRODUCTS[:ISSUES] => features_issues_path,
      PRODUCTS[:PACKAGES] => features_packages_path,
      PRODUCTS[:SECURITY] => enterprise_advanced_security_path,
      PRODUCTS[:SERVICES] => services_path,
    }
  end
end
