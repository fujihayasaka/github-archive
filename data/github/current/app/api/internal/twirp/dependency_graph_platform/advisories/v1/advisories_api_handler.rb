# typed: true
# frozen_string_literal: true

require "monolith-twirp-dependency_graph_platform-advisories"

module Api::Internal::Twirp::DependencyGraphPlatform
  module Advisories
    module V1
      class AdvisoriesAPIHandler < Api::Internal::Twirp::Handler
        Proto = Github::DependencyGraphPlatform::GhInternal::Advisories::V1

        allow_access_for :client, allowed_clients: ["dependency_graph_platform"]
        handles_service Proto::AdvisoriesAPIService

        sig do
          params(
            req: Proto::ListCurrentVulnerableVersionRangesRequest,
            env: T::Hash[String, T.untyped]
          ).returns(
            T.any(
              Proto::ListCurrentVulnerableVersionRangesResponse,
              Twirp::Error
            )
          )
        end
        def list_current_vulnerable_version_ranges(req, env)
          unless req.ecosystem.present?
            return Twirp::Error.invalid_argument("ecosystem must be provided", argument: "ecosystem")
          end

          ecosystem = case req.ecosystem
          when :ECOSYSTEM_NPM
            AdvisoryDB::Ecosystems::NPM
          else
            return Twirp::Error.invalid_argument("unexpected ecosystem", argument: "ecosystem")
          end

          # We can safely list all published vulnerable version ranges for the requested ecosystem,
          # given that no alerts are going to be created without
          # calling repository_vulnerability_alerter.create_alerts later.
          vvrs = VulnerableVersionRange.joins(:vulnerability).merge(Vulnerability.published).
            where(ecosystem: ecosystem.name).
            select(:id, :ecosystem, :affects, :requirements, :vulnerability_id).
            preload(:vulnerability)

          Proto::ListCurrentVulnerableVersionRangesResponse.new({
            vulnerable_version_ranges: vvrs.map(&method(:proto_vvr))
          })
        end

        private

        sig do
          params(vvr: VulnerableVersionRange).returns(Proto::VulnerableVersionRange)
        end
        def proto_vvr(vvr)
          vulnerability = T.must(vvr.vulnerability)

          Proto::VulnerableVersionRange.new(
            ecosystem: proto_ecosystem(vvr.ecosystem),
            github_id: vvr.id,
            package_name: vvr.affects,
            requirements: vvr.requirements,
            visibility_scope: proto_visibility_scope(vulnerability.visibility),
            # Performance: owner_type/owner_id are already-loaded columns. Loading the
            # polymorphic owner object would add a DB query just to extract its ID.
            owner_business_id: vulnerability.owner_type == Business.name ? vulnerability.owner_id : nil,
            owner_org_id: vulnerability.owner_type == Organization.base_class.name ? vulnerability.owner_id : nil,
          )
        end

        def proto_ecosystem(ecosystem)
          case ecosystem
          when "npm"
            Proto::Ecosystem::ECOSYSTEM_NPM
          else
            Proto::Ecosystem::ECOSYSTEM_INVALID
          end
        end

        def proto_visibility_scope(visibility_scope)
          case visibility_scope
          when "open_source"
            Proto::VisibilityScope::VISIBILITY_SCOPE_OPEN_SOURCE
          when "innersource"
            Proto::VisibilityScope::VISIBILITY_SCOPE_INNERSOURCE
          else
            Proto::VisibilityScope::VISIBILITY_SCOPE_INVALID
          end
        end
      end
    end
  end
end
