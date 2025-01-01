# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module EditorPreviewFeatures
        class Unconfigured < Copilot::Policies::MenuItems::EditorPreviewFeatures::Base
          private

          sig { override.returns(T::Boolean) }
          def checked?
            return @checked unless @checked.nil?

            !editor_preview_features_enabled? && !editor_preview_features_disabled?
          end

          sig { override.returns(String) }
          def type
            "button"
          end

          sig { override.returns(T::Boolean) }
          def render?
            false
          end
        end
      end
    end
  end
end
