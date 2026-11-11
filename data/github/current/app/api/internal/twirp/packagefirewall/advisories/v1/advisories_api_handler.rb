# typed: true
# frozen_string_literal: true

require "monolith-twirp-packagefirewall-package_firewall"

module Api::Internal::Twirp::Packagefirewall
  module Advisories
    module V1
      # Handler for the MonolithTwirp::Packagefirewall::Advisories::V1::AdvisoriesAPIService
      #
      # Provides two RPCs for the package-firewall service:
      #   - ListAdvisories: bulk paginated fetch of advisories by ecosystem (cache warmer path)
      #   - GetAdvisoriesForPackage: targeted advisory lookup by ecosystem + package (cache miss path)
      class AdvisoriesAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: %w(package_firewall packagefirewall)
        handles_service MonolithTwirp::Packagefirewall::Advisories::V1::AdvisoriesAPIService

        include Api::App::AdvisoryPaginationHelpers

        # Public: List all advisories for an ecosystem, paginated.
        #
        # req - The Twirp request (ListAdvisoriesRequest).
        # env - The Twirp environment Hash.
        #
        # Returns a Hash for ListAdvisoriesResponse, or a Twirp::Error.
        def list_advisories(req, env)
          return Twirp::Error.invalid_argument("must be non-empty", argument: "ecosystem") if req.ecosystem.blank?

          query = base_advisory_query.where(vulnerable_version_ranges: { ecosystem: req.ecosystem })

          params = {
            after: req.after.presence,
            per_page: req.per_page > 0 ? req.per_page : 100,
          }
          advisories_relation = paginate_advisories(query, params)
          advisories = advisories_relation.edge_nodes.sync

          {
            advisories: build_advisory_list(advisories),
            next_page_token: advisories_relation.has_next_page ? advisories_relation.page_info.end_cursor : nil,
          }
        rescue Platform::Errors::Cursor,
          Platform::Errors::InvalidPagination => e
          Twirp::Error.invalid_argument(e.message, argument: "after")
        rescue Platform::Errors::ExcessivePagination => e
          Twirp::Error.invalid_argument(e.message, argument: "per_page")
        end

        # Public: Get advisories affecting a specific package.
        #
        # req - The Twirp request (GetAdvisoriesForPackageRequest).
        # env - The Twirp environment Hash.
        #
        # Returns a Hash for GetAdvisoriesForPackageResponse, or a Twirp::Error.
        def get_advisories_for_package(req, env)
          return Twirp::Error.invalid_argument("must be non-empty", argument: "ecosystem") if req.ecosystem.blank?
          return Twirp::Error.invalid_argument("must be non-empty", argument: "package_name") if req.package_name.blank?

          query = base_advisory_query.where(
            vulnerable_version_ranges: {
              ecosystem: req.ecosystem,
              affects: req.package_name,
            }
          )

          advisory_type = normalize_advisory_type(req.type)
          if advisory_type.is_a?(Twirp::Error)
            return advisory_type
          end

          if advisory_type && advisory_type != :ADVISORY_TYPE_UNSPECIFIED
            classification = TYPE_TO_CLASSIFICATION[advisory_type]
            query = query.where(classification: classification)
          end

          advisories = query.to_a

          { advisories: build_advisory_list(advisories) }
        end

        private

        # Normalize a protobuf AdvisoryType enum value to a Symbol.
        #
        # Protobuf enum fields return Symbols for known values and Integers
        # for unrecognized wire values. This normalizes both representations
        # and returns a Twirp::Error for values that cannot be mapped.
        def normalize_advisory_type(raw_type)
          return nil if raw_type.nil?

          type_sym = if raw_type.is_a?(Integer)
            MonolithTwirp::Packagefirewall::Advisories::V1::AdvisoryType.lookup(raw_type)
          else
            raw_type
          end

          return Twirp::Error.invalid_argument("unknown advisory type", argument: "type") if type_sym.nil?

          unless type_sym == :ADVISORY_TYPE_UNSPECIFIED || TYPE_TO_CLASSIFICATION.key?(type_sym)
            return Twirp::Error.invalid_argument("unknown advisory type", argument: "type")
          end

          type_sym
        end

        def base_advisory_query
          Vulnerability.open_source.disclosed
        end

        def build_advisory_list(advisories)
          GitHub::PrefillAssociations.prefill_associations(advisories, [:vulnerable_version_ranges])

          advisories.map do |advisory|
            next {} unless advisory

            {
              ghsa_id: advisory.ghsa_id,
              severity: severity_to_proto(advisory.severity),
              type: classification_to_proto(advisory.classification),
              vulnerabilities: build_vulnerabilities(advisory.vulnerable_version_ranges),
              published_at: proto_timestamp(advisory.published_at),
              withdrawn_at: proto_timestamp(advisory.withdrawn_at),
            }
          end
        end

        def build_vulnerabilities(vulnerable_version_ranges)
          vulnerable_version_ranges.map do |vvr|
            next {} unless vvr

            {
              package: {
                ecosystem: vvr.ecosystem,
                name: vvr.affects,
              },
              vulnerable_version_range: vvr.requirements,
              first_patched_version: vvr.fixed_in,
            }
          end
        end

        SEVERITY_MAP = {
          "low" => :SEVERITY_LOW,
          "moderate" => :SEVERITY_MEDIUM,
          "high" => :SEVERITY_HIGH,
          "critical" => :SEVERITY_CRITICAL,
        }.freeze

        def severity_to_proto(severity)
          return :SEVERITY_UNSPECIFIED if severity.nil?

          SEVERITY_MAP[severity.to_s] || :SEVERITY_UNSPECIFIED
        end

        CLASSIFICATION_MAP = {
          "general" => :ADVISORY_TYPE_REVIEWED,
          "malware" => :ADVISORY_TYPE_MALWARE,
          "unknown" => :ADVISORY_TYPE_UNREVIEWED,
        }.freeze

        TYPE_TO_CLASSIFICATION = {
          ADVISORY_TYPE_REVIEWED: "general",
          ADVISORY_TYPE_MALWARE: "malware",
          ADVISORY_TYPE_UNREVIEWED: "unknown",
        }.freeze

        def classification_to_proto(classification)
          return :ADVISORY_TYPE_UNSPECIFIED if classification.nil?

          CLASSIFICATION_MAP[classification.to_s] || :ADVISORY_TYPE_UNSPECIFIED
        end

        def proto_timestamp(timestamp)
          return nil unless timestamp

          Google::Protobuf::Timestamp.new(seconds: timestamp.to_i, nanos: timestamp.nsec)
        end
      end
    end
  end
end
