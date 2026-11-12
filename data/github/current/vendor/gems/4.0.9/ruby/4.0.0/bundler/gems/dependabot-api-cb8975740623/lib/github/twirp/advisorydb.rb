# typed: strict
# frozen_string_literal: true

require "twirp"
require "sorbet-runtime"
require "monolith-twirp-advisorydb-advisories"

module GitHub
  module Twirp
    class Advisorydb
      extend T::Sig

      class Error < StandardError; end

      AdvisoriesApi = MonolithTwirp::AdvisoryDB::Advisories::V1

      class VulnerableVersionRange < T::Struct
        const :package, T::Hash[Symbol, String]
        const :vulnerable_version_range, String
      end

      class Advisory < T::Struct
        const :ghsa_id, String
        const :cve_id, T.nilable(String)
        const :severity, T.nilable(String)
        const :classification, T.nilable(String)
        const :vulnerable_version_ranges, T::Array[VulnerableVersionRange]
        const :published_at, T.nilable(Time)
        const :updated_at, T.nilable(Time)
        const :origin, T.nilable(T::Hash[Symbol, String])
      end

      class AdvisoriesResponse < T::Struct
        const :advisories, T::Array[Advisory]
      end

      sig { params(client: GitHub::Twirp::Client).void }
      def initialize(client:)
        @client = client
        @list_advisories_api = T.let(nil, T.nilable(AdvisoriesApi::ListAdvisoriesAPIClient))
      end

      sig do
        params(input: T::Hash[Symbol, T.untyped]).returns(T.any(AdvisoriesResponse, T.noreturn))
      end
      def request_advisories(input)
        raise Error, "Package list cannot be empty" if input[:packages].empty?

        response = list_advisories(input)
        raise Error, "Failed to request advisories: #{response.error.msg}" if response.error

        AdvisoriesResponse.new(advisories: advisories_from(response))
      end

      private

      delegate :list_advisories, to: :list_advisories_api

      sig { returns(AdvisoriesApi::ListAdvisoriesAPIClient) }
      def list_advisories_api
        @list_advisories_api ||= AdvisoriesApi::ListAdvisoriesAPIClient.new(@client.connection)
      end

      sig { params(response: ::Twirp::ClientResp).returns(T::Array[Advisory]) }
      def advisories_from(response)
        response.data.advisories.map(&method(:advisory_from))
      end

      sig { params(advisory: AdvisoriesApi::Advisory).returns(Advisory) }
      def advisory_from(advisory)
        Advisory.new(
          ghsa_id: advisory.ghsa_id,
          cve_id: advisory.cve_id,
          severity: advisory.severity.to_s,
          classification: advisory.classification.to_s,
          vulnerable_version_ranges: version_ranges_from(advisory),
          published_at: advisory.published_at&.to_time,
          updated_at: advisory.updated_at&.to_time,
          origin: { source: T.unsafe(advisory.origin).source.to_s }
        )
      end

      sig { params(advisory: AdvisoriesApi::Advisory).returns(T::Array[VulnerableVersionRange]) }
      def version_ranges_from(advisory)
        advisory.vulnerable_version_ranges.map do |range|
          VulnerableVersionRange.new(
            package: { ecosystem: T.unsafe(range).package.ecosystem.to_s, name: T.unsafe(range).package.name },
            vulnerable_version_range: T.unsafe(range).vulnerable_version_range
          )
        end
      end
    end
  end
end
