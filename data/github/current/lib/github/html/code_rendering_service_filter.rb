# typed: true
# frozen_string_literal: true

module GitHub::HTML
  class CodeRenderingServiceFilter < ::HTML::Pipeline::Filter
    def call
      doc.search(CodeRenderingService.selector_list).each do |node|
        view_data = node.children.first.inner_html
        return node if view_data.blank?
        ui = CodeRenderingService.for_markdown(node["lang"].to_sym, context[:page], view_data, opts: { html_safe: result[:html_safe] })
        return node if !ui.supports_view?

        content = ApplicationController.render(ui, formats: [:html], layout: false)
        node.replace(content)
      end

      doc
    end
  end
end
