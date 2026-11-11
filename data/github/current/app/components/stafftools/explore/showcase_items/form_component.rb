# typed: true
# frozen_string_literal: true

module Stafftools
  module Explore
    module ShowcaseItems
      class FormComponent < Stafftools::Explore::BaseComponent
        def initialize(showcase:, item:, context: Stafftools::Explore::BaseComponent::DEFAULT_CONTEXT)
          super(context: context)
          @showcase = showcase
          @item     = item
        end

        private

        attr_reader :showcase, :item

        def render?
          return false unless GitHub.showcase_enabled?

          showcase.present? && item.present?
        end

        def show_header?
          item.persisted?
        end

        def nwo_value
          return unless item.item.present?
          item.item.name_with_owner
        end

        def back_path
          if stafftools?
            stafftools_showcase_collection_path(showcase)
          else
            biztools_showcase_collection_path(showcase)
          end
        end

        def healthcheck_path
          if stafftools?
            stafftools_showcase_collection_healthcheck_path(showcase)
          else
            biztools_showcase_collection_healthcheck_path(showcase)
          end
        end
      end
    end
  end
end
