# typed: true
# frozen_string_literal: true

require "monolith-twirp-advisorydb-advisories"

module Api::Internal::Twirp::AdvisoryDB
  module Advisories
    module V1
      # Handler for the MonolithTwirp::AdvisoryDB::Advisories::V1::ListAdvisoriesAPIService
      class ListAdvisoriesAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["advisorydb"]
        handles_service MonolithTwirp::AdvisoryDB::Advisories::V1::ListAdvisoriesAPIService

        include AdvisoryDB::GlobalAdvisoriesApiHelper
        include Api::App::AdvisoryPaginationHelpers

        # Public: Implementation of the ListAdvisories Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::AdvisoryDB::Advisories::V1::ListAdvisoriesRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::AdvisoryDB::Advisories::V1::ListAdvisoriesResponse, or a Twirp::Error.
        def list_advisories(req, env)
          if req.packages.empty?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "packages")
          end

          # Only search on open source vulnerabilities if no repo_id is provided
          base_query = Vulnerability.disclosed

          if req.repo_id != 0
            return Twirp::Error.invalid_argument("Querying by repo_id not currently supported", argument: "repo_id")
          end

          # Search for each of the packages
          packages = req.packages

          query = T.let(
            base_query.where(
              vulnerable_version_ranges: {
                affects: packages.first.name,
                ecosystem: ECOSYSTEM_HASH.key(packages.first.ecosystem)
              }
            ),
            ActiveRecord::Relation
          )

          packages[1..].each do |package|
            query = query.or(
              base_query.where(
                vulnerable_version_ranges: {
                  affects: package.name,
                  ecosystem: ECOSYSTEM_HASH.key(package.ecosystem)
                }
              )
            )
          end

          # Sort the advisories
          sort_by = req&.options&.sort_by
          sort_by = :SORT_BY_PUBLISHED if sort_by.nil? || sort_by == :SORT_BY_INVALID
          sort_by = sort_by.to_s.delete_prefix("SORT_BY_").downcase

          direction = req&.options&.direction || :DIRECTION_DESC
          direction = :DIRECTION_DESC if direction.nil? || direction == :DIRECTION_INVALID
          direction = direction.to_s.delete_prefix("DIRECTION_").downcase || "desc"

          query = sort_advisories(query, sort_by:, direction:, current_user: current_user)

          # Paginate the advisories
          params = {
            after: req.next_page_token,
            per_page: req&.options&.per_page || 100,
          }
          advisories_platform_relation = paginate_advisories(query, params)
          advisories = advisories_platform_relation.edge_nodes.sync

          # Return the formatted response
          {
            advisories: build_advisory_list(advisories, innersource: false),
            next_page_token: advisories_platform_relation.has_next_page ? advisories_platform_relation.page_info.end_cursor : nil
          }
        rescue Platform::Errors::Cursor,
          Platform::Errors::InvalidPagination => e
          Twirp::Error.invalid_argument(e.message, argument: "next_page_token")
        rescue Platform::Errors::ExcessivePagination => e
          Twirp::Error.invalid_argument(e.message, argument: "per_page")
        end

        private

        # Private: Convert an array of Vulnerability objects to the Twirp response ListAdvisoriesResponse.
        #
        # advisories - The array of Vulnerability objsects.
        #
        # Returns an array of Hash objects with vulnerability data that matches the
        # Twirp definition.
        def build_advisory_list(advisories, innersource: false)
          associations = T.let(
            [
              :vulnerable_version_ranges,
            ],
            T::Array[T.any(Symbol, T::Hash[Symbol, Symbol])]
          )
          if innersource
            associations << {
              repository_advisory: {
                repository: {
                  organization: :business,
                },
              },
            }
          end
          GitHub::PrefillAssociations.prefill_associations(advisories, associations)

          advisories.map do |advisory|
            next {} unless advisory

            advisory_hash = {
              ghsa_id: advisory.ghsa_id,
              cve_id: advisory.cve_id,
              severity: get_advisory_severity(advisory),
              classification: get_advisory_classification(advisory),
              vulnerable_version_ranges: build_vulnerable_version_ranges_list(advisory.vulnerable_version_ranges),
              published_at: proto_timestamp(advisory.published_at),
              withdrawn_at: proto_timestamp(advisory.withdrawn_at),
              updated_at: proto_timestamp(advisory.updated_at),
              reviewed_at: proto_timestamp(advisory.reviewed_at),
              nvd_published_at: proto_timestamp(advisory.nvd_published_at),
              origin: {
                source: :SOURCE_OPEN_SOURCE,
              },
            }
            if advisory_hash[:origin][:source] == :SOURCE_INNERSOURCE
              advisory_hash[:origin][:origin] = {
                repository_advisory_id: advisory.security_advisory_id,
                repository_id: advisory.advisory_repository_id,
                organization_id: advisory.repository_advisory.organization.id,
                business_id: advisory.repository_advisory.organization.business.id,
              }
            end

            advisory_hash
          end
        end

        def build_vulnerable_version_ranges_list(vulnerable_version_ranges)
          vulnerable_version_ranges.map do |vvr|
            next {} unless vvr

            {
              package: {
                ecosystem: get_vvr_ecosystem(vvr),
                name: vvr.affects,
              },
              vulnerable_version_range: vvr.requirements,
              first_patched_version: vvr.fixed_in,
              affected_functions: vvr.affected_functions,
              affected_functions_json: vvr.affected_functions_json.to_s,
            }
          end
        end

        CLASSIFICATION_HASH = {
          "unknown": :CLASSIFICATION_UNKNOWN,
          "general": :CLASSIFICATION_GENERAL,
          "malware": :CLASSIFICATION_MALWARE,
        }

        def get_advisory_classification(advisory)
          CLASSIFICATION_HASH[advisory.classification.to_sym]
        end

        SEVERITY_HASH = {
          "low": :SEVERITY_LOW,
          "moderate": :SEVERITY_MEDIUM,
          "high": :SEVERITY_HIGH,
          "critical": :SEVERITY_CRITICAL,
        }

        def get_advisory_severity(advisory)
          return :SEVERITY_UNKNOWN if advisory.severity.nil?

          SEVERITY_HASH[advisory.severity.to_sym]
        end

        SOURCE_HASH = {
          "innersource": :SOURCE_INNERSOURCE,
          "open_source": :SOURCE_OPEN_SOURCE,
        }

        def get_advisory_source(advisory)
          SOURCE_HASH[advisory.scope.to_sym]
        end

        ECOSYSTEM_HASH = {
          "RubyGems": :ECOSYSTEM_RUBYGEMS,
          "npm": :ECOSYSTEM_NPM,
          "pip": :ECOSYSTEM_PIP,
          "maven": :ECOSYSTEM_MAVEN,
          "nuget": :ECOSYSTEM_NUGET,
          "composer": :ECOSYSTEM_COMPOSER,
          "go": :ECOSYSTEM_GO,
          "rust": :ECOSYSTEM_RUST,
          "erlang": :ECOSYSTEM_ERLANG,
          "swift": :ECOSYSTEM_SWIFT,
          "other": :ECOSYSTEM_OTHER,
          "actions": :ECOSYSTEM_ACTIONS,
          "pub": :ECOSYSTEM_PUB,
          "alpm": :ECOSYSTEM_ALPM,
          "apk": :ECOSYSTEM_APK,
          "bitbucket_repository": :ECOSYSTEM_BITBUCKET,
          "cocoapods": :ECOSYSTEM_COCOAPODS,
          "conan_center": :ECOSYSTEM_CONAN,
          "conda_forge": :ECOSYSTEM_CONDA,
          "cran": :ECOSYSTEM_CRAN,
          "deb": :ECOSYSTEM_DEB,
          "docker_hub": :ECOSYSTEM_DOCKER,
          "github_repository": :ECOSYSTEM_GITHUB,
          "hackage": :ECOSYSTEM_HACKAGE,
          "huggingface": :ECOSYSTEM_HUGGINGFACE,
          "mlflow": :ECOSYSTEM_MLFLOW,
          "qpkg": :ECOSYSTEM_QPKG,
          "oci": :ECOSYSTEM_OCI,
          "rpm": :ECOSYSTEM_RPM,
          "swid": :ECOSYSTEM_SWID,
          "generic": :ECOSYSTEM_GENERIC,
        }

        def get_vvr_ecosystem(vvr)
          ECOSYSTEM_HASH[vvr.ecosystem.to_sym]
        end

        def proto_timestamp(timestamp)
          return nil unless timestamp

          Google::Protobuf::Timestamp.new(seconds: timestamp.to_i, nanos: timestamp.nsec)
        end
      end
    end
  end
end
