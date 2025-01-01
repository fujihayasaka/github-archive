# typed: true
# frozen_string_literal: true

module Stafftools
  module Models
    class LogoComponent < ApplicationComponent
      sig { params(catalog_item: GitHubModels::CatalogItem, system_arguments: T.untyped).void }
      def initialize(catalog_item:, **system_arguments)
        @catalog_item = catalog_item
        @system_arguments = system_arguments
      end

      def call
        base_attrs = {
          tag: :img,
          src: img_src,
          test_selector: "model-logo",
          height: 16,
          width: 16,
          alt: catalog_item.name,
        }
        system_args = { mr: 1 }.merge(@system_arguments)
        attrs = base_attrs.merge(system_args)
        render Primer::BaseComponent.new(**T.unsafe(**attrs))
      end

      private

      sig { returns GitHubModels::CatalogItem }
      attr_reader :catalog_item

      sig { returns T::Boolean }
      def render?
        img_src.present?
      end

      sig { returns T.nilable(String) }
      memoize def img_src
        catalog_item.icon_src(dark_mode: helpers.viewer_using_dark_color_mode?)
      end
    end
  end
end
