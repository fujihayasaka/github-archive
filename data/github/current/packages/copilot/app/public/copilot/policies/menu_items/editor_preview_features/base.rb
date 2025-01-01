# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module EditorPreviewFeatures
        class Base < Copilot::Policies::MenuItems::Base
          abstract!

          private

          delegate :editor_preview_features_enabled?, :editor_preview_features_disabled?, :editor_preview_features_no_policy?, to: :copilot_configurable

          sig { override.returns(String) }
          def name
            "copilot_editor_preview_features"
          end
        end
      end
    end
  end
end
