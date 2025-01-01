# typed: strict
# frozen_string_literal: true

module ContextRegion
  class ReactCoreExamplesCrumb < Crumb
    include UrlHelpers

    sig { override.returns(String) }
    def label
      "React Core Examples"
    end

    sig { override.returns(T.nilable(Symbol)) }
    def path_name
      :_react_core_examples_index_path
    end

    sig { override.returns(Site::Header::UnderlineNavComponent) }
    def header_navigation_component
      Site::Header::UnderlineNavComponent.new(
        label: "User",
        tabs: [
          Site::Header::UnderlineNavTab.new(
            text: "DataRouter",
            icon: :book,
            href: _react_core_examples_index_path,
          ),
        ]
      )
    end
  end
end
