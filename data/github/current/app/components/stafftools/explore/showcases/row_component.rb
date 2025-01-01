# typed: true
# frozen_string_literal: true

module Stafftools
  module Explore
    module Showcases
      class RowComponent < Stafftools::Explore::BaseComponent

        def initialize(collection:, show_badges: true, context:)
          super(context: context)
          @collection  = collection
          @show_badges = fetch_or_fallback([true, false], show_badges, true)
        end

        private

        attr_reader :collection, :show_badges, :variant
        alias :show_badges? :show_badges

        def render?
          return false unless GitHub.showcase_enabled?
          collection.present?
        end

        def show_url
          if stafftools?
            stafftools_showcase_collection_path(collection)
          else
            biztools_showcase_collection_path(collection)
          end
        end

        def form_url
          if stafftools?
            featured_stafftools_showcase_collection_path(collection)
          else
            featured_biztools_showcase_collection_path(collection)
          end
        end

        def edit_url
          if stafftools?
            edit_stafftools_showcase_collection_path(collection)
          else
            edit_biztools_showcase_collection_path(collection)
          end
        end
      end
    end
  end
end
