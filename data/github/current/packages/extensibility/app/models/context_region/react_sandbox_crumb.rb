# typed: true
# frozen_string_literal: true

module ContextRegion
  class ReactSandboxCrumb < Crumb
    include UrlHelpers

    def label
      "React Sandbox"
    end

    def path_name
      :_react_sandbox_index_path
    end

    def header_navigation_component
      Site::Header::UnderlineNavComponent.new(
        label: "User",
        tabs: [
          Site::Header::UnderlineNavTab.new(
            text: "Index",
            icon: :book,
            href: _react_sandbox_index_path,
            count: 42
          ),
          Site::Header::UnderlineNavTab.new(
            text: "Show 1",
            icon: :book,
            href: _react_sandbox_show_path(1),
          ),
          Site::Header::UnderlineNavTab.new(
            text: "Show 2",
            icon: :book,
            href: _react_sandbox_show_path(2),
          )
        ]
      )
    end
  end
end
