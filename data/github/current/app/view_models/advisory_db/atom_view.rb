# typed: true
# frozen_string_literal: true

module AdvisoryDB
  class AtomView
    attr_reader :view

    FeedAuthor = Struct.new(:name)
    NullAdvisory = Struct.new(:ghsa_id, :updated_at)

    def initialize(view)
      @view = view
      days = GitHub.flipper[:advisories_atom_decrease_days].enabled? ? 8.days : 14.days
      @updated_after = days.ago.beginning_of_day
    end

    def cache_key
      "feeds:%s:%s:%s" % [Digest::SHA256.hexdigest(self_url), most_recently_updated.ghsa_id, most_recently_updated.updated_at.to_i]
    end

    def feed_id
      ["tag:", GitHub.host_name, ",2008:", view.security_advisory_feed_path].join
    end

    def feed_title
      "GitHub Security Advisory Feed"
    end

    def feed_author
      FeedAuthor.new("GitHub")
    end

    def self_url
      view.security_advisory_feed_url(format: :atom)
    end

    def feed_updated_at
      most_recently_updated.updated_at.utc.iso8601
    end

    def advisories
      @advisories ||= disclosed_advisories.map do |advisory|
        advisory = AtomAdvisory.new(advisory)
        advisory.valid? ? advisory : nil
      end.compact
    end

    private

    def most_recently_updated
      @most_recently_updated ||= disclosed_advisories.first || null_advisory
    end

    def null_advisory
      NullAdvisory.new("N/A", Time.now.utc)
    end

    def disclosed_advisories
      return @disclosed_advisories if defined? @disclosed_advisories

      base_query = SecurityAdvisory.disclosed
                                   .has_been_reviewed
                                   .where("vulnerabilities.updated_at > ?", @updated_after)
                                   .order(updated_at: :desc)
                                   .preload(:cwes)

      @disclosed_advisories = if GitHub.flipper[:advisories_atom_decrease_queries].enabled?
        base_query.preload(:vulnerabilities)
      else
        base_query
      end.to_a
    end

    class AtomAdvisory
      attr_reader :advisory

      delegate :ghsa_id, :references, :cwes, :cvss_v3, :cvss_v3_score, to: :advisory

      def initialize(advisory)
        @advisory = advisory
      end

      def id
        "tag:%s,2008:%s" % [GitHub.host_name, advisory.ghsa_id]
      end

      def title
        advisory.summary(atom: true)
      end

      def categories
        advisory.public_vulnerabilities.pluck(:ecosystem).sort.uniq.map(&:upcase)
      end

      def content
        return @content if defined? @content
        @content = begin
          html_content = GitHub::Goomba::MarkdownPipeline.to_html(advisory.description)
          GitHub::Goomba::NoReferrerPipeline.to_html(html_content)
        rescue EncodingError, TypeError => e
          Failbot.report(e, "gh.ghsa_id": advisory.ghsa_id, "gh.global_advisory.description": advisory.description)
          nil
        end
      end

      def vulnerabilities
        @vulnerabilities ||= advisory.public_vulnerabilities.map do |vulnerability|
          AtomVulnerability.new(vulnerability)
        end
      end

      def published_at
        advisory.published_at.utc.iso8601
      end

      def updated_at
        advisory.updated_at.utc.iso8601
      end

      def valid?
        content.present? && advisory.published_at.present?
      end
    end

    class AtomVulnerability
      attr_reader :vulnerability

      delegate :severity, :vulnerable_version_range, to: :vulnerability

      def initialize(vulnerability)
        @vulnerability = vulnerability
      end

      def name
        vulnerability.package[:name]
      end

      def ecosystem
        vulnerability.package[:ecosystem].downcase
      end

      # This breaks the facade on the VulnerableVersionRange model for convenience to
      # avoid testing for a nil value for SecurityVulnerability#first_patched_version
      def first_patched_version
        vulnerability.fixed_in
      end
    end
  end
end
