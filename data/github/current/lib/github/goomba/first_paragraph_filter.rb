# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  # Output filter that extracts the first HTML paragraph into
  # result[:first_paragraph]
  class FirstParagraphFilter < OutputFilter
    def call(html)
      first_para = Goomba::DocumentFragment.new(html).select("p").first&.to_html
      first_para = html if first_para.nil?
      result[:first_paragraph] = safe_html_if_sanitized(first_para)
      html
    end
  end
end
