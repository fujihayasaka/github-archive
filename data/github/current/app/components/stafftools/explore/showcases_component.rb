# typed: true
# frozen_string_literal: true

module Stafftools
  module Explore
    class ShowcasesComponent < Stafftools::Explore::BaseComponent
      def initialize(featured: false, context: Stafftools::Explore::BaseComponent::DEFAULT_CONTEXT)
        super(context: context)
        @featured = fetch_or_fallback([true, false], featured, false)
      end

      private

      attr_reader :featured
      alias :featured? :featured

      def render?
        GitHub.showcase_enabled?
      end

      def heading
        featured? ? "Featured showcases" : "Showcases"
      end

      def new_button_text
        featured? ? "New showcase" : "New collection"
      end

      def new_url
        if stafftools?
          new_stafftools_showcase_collection_path
        else
          new_biztools_showcase_collection_path
        end
      end

      def collections
        @collections ||= if featured?
          ::Showcase::Collection.featured
        else
          ::Showcase::Collection.order("published ASC, name ASC")
        end
      end
    end
  end
end
