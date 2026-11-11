# typed: strict
# frozen_string_literal: true

module Site
  module Contentful
    module Swp
      module Page
        module Settings
          extend T::Helpers

          requires_ancestor { Site::Contentful::Swp::Page::Traversal }

          sig { returns(String) }
          def feature_flag
            page_settings&.fetch("featureFlag", "") || ""
          end

          sig { returns(T::Boolean) }
          def use_dark_mode?
            page_settings&.fetch("colorMode", nil) == "dark"
          end

          sig { returns(T.nilable(String)) }
          def global_navbar_style
            style = page_settings&.fetch("globalNavbarStyle", nil)
            return if style.blank? || style == "default"
            style
          end

          sig { returns(T.nilable(String)) }
          def revenue_play
            page_settings&.fetch("revenuePlay", nil)
          end

          sig { returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
          def page_settings
            (get_field("settings") || {}).fetch("fields", {})
          end
        end
      end
    end
  end
end
