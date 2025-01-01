# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  class CVEMentionFilter < NodeFilter
    SELECTOR = Goomba::Selector.new(match: ":text",
                                    reject: "pre :text, code :text, a :text, blockquote :text")

    CVE_ID_PATTERN = /cve-\d{4}-\d{4,}/i

    def call(node)
      call_text(node)
    end

    # Turns plain text CVE IDs into <gh:cve-mention> tags
    #
    # replaces:
    # CVE_ID_PATTERN
    #
    # with:
    # <gh:cve-mention cve_id="CVE_ID_PATTERN"></gh:cve-mention>
    #
    def call_text(text)
      text.html.gsub(CVE_ID_PATTERN) { |match| cve_mention_tag(match) }
    end

    def selector
      SELECTOR
    end

    private

    # returns an html_safe gh:cve-mention tag
    def cve_mention_tag(cve_id)
      ActionController::Base.helpers.content_tag("gh:cve-mention", nil, { cve_id: cve_id })
    end
  end
end
