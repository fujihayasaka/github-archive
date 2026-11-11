# typed: true
# frozen_string_literal: true

module GitHub::HTML
  class CodeRenderingServiceFilter < ::HTML::Pipeline::Filter
    def call
      doc.search(CodeRenderingService.selector_list).each do |node|
        if skip_quote_rewrite?
          # Use the decoded text content rather than the serialized HTML of the
          # code block: the component escapes what it renders, so handing it
          # markup would let attributes the sanitizer rejected survive.
          view_data = node.text
          opts = { skip_quote_rewrite: true }
        else
          view_data = node.children.first.inner_html
          opts = { html_safe: result[:html_safe] }
        end
        return node if view_data.blank?

        ui = CodeRenderingService.for_markdown(node["lang"].to_sym, context[:page], view_data, opts: opts)
        return node if !ui.supports_view?

        content = ApplicationController.render(ui, formats: [:html], layout: false)
        node.replace(content)
      end

      doc
    end

    private

    # See GitHub::Goomba::CodeRenderingServiceFilter::SKIP_QUOTE_REWRITE_FLAG.
    def skip_quote_rewrite?
      actor = context[:page]
      if actor.respond_to?(:vexi_id)
        FeatureFlag.vexi.enabled?(GitHub::Goomba::CodeRenderingServiceFilter::SKIP_QUOTE_REWRITE_FLAG, actor, default: false)
      else
        FeatureFlag.vexi.enabled?(GitHub::Goomba::CodeRenderingServiceFilter::SKIP_QUOTE_REWRITE_FLAG, default: false)
      end
    end
  end
end
