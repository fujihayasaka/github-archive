# frozen_string_literal: true

module AdvisoryDB
  module Config
    module Sources
      # SOURCE_CONFIG defines all the various sources that feed entries come from
      #
      # WARNING: Always add new sources to the end of the hash!
      # Also, Never remove a source once added.
      # The reason for this is because it is used an an enum in FeedEntry, and order should never change for an enum.
      #
      # Configuration relevant to each source is defined here too.
      # - importer: (true/false). Whether a corresponding Importer class exists for a given source.
      # - subject_to_blocklist: (true/false). Defines whether the BlockList feature is applied to
      #   advisory reviews with feed entries from the source.
      # - trusted: (true/false). Designates whether we can trust-by-default that the data from the source is
      #   intended to be non-malicious. Still needs to be verified during the advisory review process.
      # - ai_prediction: (true/false). Whether a source is eligiable to call CAPI for ecosystem and package
      #   name predictions
      #
      SOURCE_CONFIG = {
        "nvd" => {
          importer: true,
          subject_to_blocklist: true,
          trusted: true,
          ai_prediction: true,
        },
        # white_source was an importer, but was removed in July 2020
        "white_source" => {
          importer: false,
          trusted: true,
        },
        # cve_list was an importer, but was removed in May 2022
        "cve_list" => {
          importer: false,
          trusted: true,
        },
        "friends_of_php" => {
          importer: true,
          trusted: true,
          ai_prediction: true,
        },
        "rubysec" => {
          importer: true,
          trusted: true,
          ai_prediction: true,
        },
        "repository_advisories" => {
          importer: true,
          trusted: true,
          ai_prediction: true,
        },
        "cve_review" => {
          importer: true,
          trusted: true,
        },
        "backfill" => {
          importer: true,
          trusted: true,
          ai_prediction: true,
        },
        "npm" => {
          importer: false,
          trusted: true,
          ai_prediction: true,
        },
        "rustsec" => {
          importer: true,
          trusted: true,
          ai_prediction: true,
        },
        "advisory_improvement" => {
          importer: true,
          trusted: false,
        },
        "pypa_advisory" => {
          importer: true,
          trusted: true,
          ai_prediction: true,
        },
        "malware_advisory" => {
          importer: true,
          trusted: true,
        },
        "go" => {
          importer: true,
          trusted: true,
          ai_prediction: true,
        },
      }.freeze

      def sources
        if Rails.env.test?
          SOURCE_CONFIG.keys + ["munger"]
        else
          SOURCE_CONFIG.keys
        end
      end

      def source?(source)
        sources.include?(source)
      end

      def importer_sources
        SOURCE_CONFIG.select { |_, config| config[:importer] == true }.keys
      end

      def sources_subject_to_blocklist
        SOURCE_CONFIG.select { |_, config| config[:subject_to_blocklist] == true }.keys
      end

      def source_subject_to_blocklist?(source)
        sources_subject_to_blocklist.include?(source)
      end

      def untrusted_sources
        SOURCE_CONFIG.select { |_, config| config[:trusted] == false }.keys
      end

      def ai_prediction_sources
        SOURCE_CONFIG.select { |_, config| config[:ai_prediction] == true }.keys
      end
    end

    include Sources
  end
end
