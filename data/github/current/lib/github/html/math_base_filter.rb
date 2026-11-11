# typed: true
# frozen_string_literal: true

module GitHub::HTML
  class MathBaseFilter < Filter
    include GitHub::Memoizer

    IGNORE_TAGS = %w(pre a b em code math-renderer).to_set
    INLINE_MATH_ALLOWED_TAGS = %w[p h1 h2 h3 h4 h5 h6 ol ul li details summary
                                table th td]
    INLINE_MATH_CSS_CLASS = "js-inline-math"
    INLINE_MATH_STYLE = "display: inline-block" # inline-block allows controlling width/overflow
    DISPLAY_MATH_CSS_CLASS = "js-display-math"
    DISPLAY_MATH_STYLE = "display: block"

    def call
      raise NotImplementedError
    end

    def self.cache_key(context)
      "mathml_filter"
    end

    protected

    def math_renderer_tag(output, css_class:, style:)
      ActionController::Base.helpers.content_tag(
        "math-renderer",
        output,
        class: css_class,
        style: style,
        data: data_attributes
      )
    end

    # This method lets us tell the math-renderer component the environment we are running in.
    def data_attributes
      {
        run_id: context[:pipeline_run_id]
      }.compact
    end
  end
end
