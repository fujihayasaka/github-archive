# typed: true
# frozen_string_literal: true

module ContextRegion
  class ReactCoreExamplesCrumb < Crumb
    include UrlHelpers

    def label
      "React Core Examples"
    end

    def path_name
      :_react_core_examples_index_path
    end

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
