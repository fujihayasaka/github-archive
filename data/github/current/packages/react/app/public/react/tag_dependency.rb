# typed: strict
# frozen_string_literal: true

module React
  module TagDependency
    extend T::Helpers
    extend ActiveSupport::Concern

    requires_ancestor { ApplicationController }

    private

    sig { params(data: T.untyped, target: T.untyped).returns(T.nilable(ActiveSupport::SafeBuffer)) }
    def html_safe_json_script_tag(data, target)
      return unless data
      content_tag(
        :script,
        json_escape(data).html_safe, # rubocop:disable Rails/OutputSafety
        type: "application/json",
        data: { target: target }
      )
    end

    sig { params(ssr_result: T.nilable(String), target: String).returns(ActiveSupport::SafeBuffer) }
    def html_safe_react_root_tag(ssr_result, target)
      content_tag(
        :div,
        ssr_result&.html_safe,  # rubocop:disable Rails/OutputSafety
        data: { target: target }
      )
    end
  end
end
