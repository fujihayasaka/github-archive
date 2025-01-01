# typed: true
# frozen_string_literal: true

module GitHub::Goomba::Async
  class CVEMentionFilter < NodeFilter
    SELECTOR = Goomba::Selector.new(match: "gh|cve-mention")

    def initialize(*args)
      super
      scratch[:vulnerabilities] = {}
    end

    def selector
      SELECTOR
    end

    def async_scan
      # Limit Rendered CVE mentions to 1000 to prevent unreasonably large queries.
      cve_ids = @nodes.first(100).map { |node| node["cve_id"].upcase }

      # Loads CVE records in one go and then writes the model to scratch for later use in call_mention_tag()
      Platform::Loaders::ActiveRecord.load_all(Vulnerability, cve_ids, column: :cve_id).then do |vulnerabilities|
        vulnerabilities.each do |vuln|
          scratch[:vulnerabilities][T.must(vuln)[:cve_id]] = vuln if vuln&.globally_available?
        end
      end
    end

    # Translates a `<gh:cve-mention>` placed into the node by
    # Goomba::CVEMentionFilter into regular HTML.
    def call(node)
      call_mention_tag(node)
    end

    def call_mention_tag(node)
      cve_id = node["cve_id"]

      if vulnerability = scratch[:vulnerabilities][cve_id.upcase]
        vulnerability_link(cve_id, vulnerability)
      else
        cve_id
      end
    end

    # Create a vulnerablity link
    #
    # cve_id - The cve id as it appears in the original text
    # vulnerablity - vulnerablity object to link to
    #
    # Returns an html-safe String link (a href) tag
    def vulnerability_link(cve_id, vulnerability)
      hovercard_attrs = HovercardHelper.hovercard_data_attributes_for_advisory(ghsa_id: vulnerability.ghsa_id)
      ActionController::Base.helpers.link_to(cve_id, vulnerability.permalink, title: vulnerability.cve_id, data: hovercard_attrs)
    end
  end
end
