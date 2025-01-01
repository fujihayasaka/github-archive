# typed: true
# frozen_string_literal: true

module ContextRegion
  class ReactSandboxFutureCrumb < Crumb
    include UrlHelpers

    def label
      "React Sandbox NEW"
    end

    def path_name
      :_react_sandbox_future_index_path
    end

    def header_navigation_component
      Site::Header::UnderlineNavComponent.new(
        label: "User",
        tabs: [
          Site::Header::UnderlineNavTab.new(
            text: "Index",
            icon: :book,
            href: _react_sandbox_future_index_path,
            count: 42
          ),
          Site::Header::UnderlineNavTab.new(
            text: "Show A-Pram",
            icon: :book,
            href: _react_sandbox_future_show_path("a-param"),
          ),
        ]
      )
    end
  end
end
