# typed: true
# frozen_string_literal: true

require_relative "../../../packages/security_products/app/models/advisory_db/cvss_score"
require_relative "../../../packages/security_products/app/models/advisory_db"

module GitHub::Goomba
  class AdvisoryMentionFilter < NodeFilter
    include AdvisoryDB::CvssScore

    NWO = ::GitHub::HTML::IssueMentionFilter::NWO
    GHSA_ID_PATTERN = ::AdvisoryDB.valid_ghsa_id_input_pattern

    def call(node)
      if is_element_node?(node) # HTML tag
        call_anchor(node) if node.tag == :a
      else # text
        call_text(node)
      end
    end

    # Handles cases where an Advisory URL has been pre-processed into an <a> tag
    # by inserting a 'gh:advisory-mention' attribute
    #
    # replaces:
    # <a href="FULL_ADVISORY_URL_PATTERN">FULL_ADVISORY_URL_PATTERN</a>
    #
    # with:
    # <a href="FULL_ADVISORY_URL_PATTERN" gh:advisory-mention="{'ghsa_id':'GHSA_ID_PATTERN'}">FULL_ADVISORY_URL_PATTERN</a>
    #
    def call_anchor(node)
      return nil unless node_is_a_bare_link?(node)

      if match = node["href"].match(full_advisory_url_pattern)
        node["gh:advisory-mention"] = advisory_attrs(ghsa_id: match[:ghsa_id]).to_json
      elsif match = node["href"].match(global_advisory_url_pattern)
        node["gh:advisory-mention"] = advisory_attrs(ghsa_id: match[:ghsa_id], global: true).to_json
      end

      nil # No replacement to return as node has been modified in place
    end

    # Turns plain text Advisory IDs into <gh:advisory-mention> tags
    #
    # replaces:
    # GHSA_ID_PATTERN
    #
    # with:
    # <gh:advisory-mention ghsa_id="GHSA_ID_PATTERN"></gh:advisory-mention>
    #
    def call_text(text)
      text.html.gsub(GHSA_ID_PATTERN) do |match|
        ActionController::Base.helpers.content_tag("gh:advisory-mention", nil, advisory_attrs(ghsa_id: match, plain_text_ghsa: true))
      end
    end

    def selector
      Goomba::Selector.new(match: ":text, a[href^='#{GitHub.url}']",
        reject: "pre :text, code :text, a :text, blockquote :text")
    end

    private

    def full_advisory_url_pattern
      %r{#{Regexp.escape(GitHub.url)}/#{NWO}/security/advisories/(?<ghsa_id>#{GHSA_ID_PATTERN})/?\z}
    end

    def global_advisory_url_pattern
      %r{#{Regexp.escape(GitHub.url)}/advisories/(?<ghsa_id>#{GHSA_ID_PATTERN})/?\z}
    end

    def node_is_a_bare_link?(node)
      node.inner_html == node["href"]
    end

    def advisory_attrs(ghsa_id:, global: false, plain_text_ghsa: false)
      attrs = { ghsa_id: AdvisoryDB.canonical_case_for_ghsa_id(ghsa_id) }
      attrs[:global] = true if global
      attrs[:plain_text_ghsa] = true if plain_text_ghsa
      attrs
    end
  end
end
