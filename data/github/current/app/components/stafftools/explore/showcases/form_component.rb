# typed: true
# frozen_string_literal: true

module Stafftools
  module Explore
    module Showcases
      class FormComponent < Stafftools::Explore::BaseComponent
        def initialize(showcase:, context: Stafftools::Explore::BaseComponent::DEFAULT_CONTEXT)
          super(context: context)
          @showcase = showcase
        end

        private

        attr_reader :showcase

        def render?
          return false unless GitHub.showcase_enabled?

          showcase.present?
        end

        def heading
          if showcase.new_record?
            "New showcase"
          else
            "Edit showcase"
          end
        end

        def deletable?
          showcase.persisted?
        end

        def delete_path
          if stafftools?
            stafftools_showcase_collection_path(showcase)
          else
            biztools_showcase_collection_path(showcase)
          end
        end
      end
    end
  end
end
