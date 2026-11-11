# typed: true
# frozen_string_literal: true

module Site
  module Contentful
    module Report
      class HeaderComponent < ApplicationComponent
        include SiteHelper
        include Site::ContentfulHelper

        def initialize(hero_image:, breadcrumbs:, hero:)
          @hero_image = hero_image
          @breadcrumbs = breadcrumbs
          @hero = hero
        end

        def render?
          @hero_image.present? && @breadcrumbs.present? && @hero.present?
        end
      end
    end
  end
end
