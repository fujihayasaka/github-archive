# typed: true
# frozen_string_literal: true

module CodeScanning
  module ResultDependency
    include TextHelper

    def result_title(result)
      if result.rule&.short_description.present?
        result.rule.short_description
      else
        result_message_text(result)
      end
    end

    def result_message_text(result)
      html = GitHub::Goomba::MarkdownPipeline.to_html(result.message_text)
      strip_tags_and_collapse_whitespace(html)
    end
  end
end
