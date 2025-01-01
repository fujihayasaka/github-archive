# typed: strict
# frozen_string_literal: true

require "github/security_center/logging_helper"

module SecurityCenter
  class CoverageExportJob < ApplicationJob
    extend T::Sig
    include GitHub::SecurityCenter::LoggingHelper

    queue_as :security_center_export

    retry_on_dirty_exit

    sig do
      params(
        scope: T.any(Organization, Business),
        user: User,
        query_string: String,
        requested_at: Time,
        user_session: T.nilable(UserSession)
      ).void
    end
    def perform(scope:, user:, query_string:, requested_at:, user_session: nil)
      parser = ::Search::Queries::SecurityCenter::CoverageQueryParser.new(query_string)
      token = Export::TokenGenerator.create_token(user:, scope:, query: parser.canonicalize, feature_type: "coverage", requested_at:,)

      status = Export::JobStatus.find(token)
      if status.nil?
        GitHub.dogstats.increment("security_center.coverage_export_job.job_status_not_found", tags: all_stats_tags)
        return
      end

      status.track do
        next if GitHub.enterprise?

        if scope.is_a?(Organization)
          authorized_orgs = [scope]
          allowed_repository_ids = log_timing(step: "Get allowed repository IDs by feature") do
            datadog_tags = [
              "controller:orgs_security_center_coverage_export",
              "feature:coverage",
              "scope:organization"
            ]
            AuthorizationEnumerator.new(user:, org: scope, datadog_tags:).adminable_repo_ids.first
          end
        else
          # TODO support Business
          authorized_orgs = []
          allowed_repository_ids = nil
        end

        repository_data = log_timing(step: "Query export data") do
          Coverage::ExportDataQuery.new(
            scope:,
            user:,
            user_session:,
            parser:,
            authorized_orgs:,
            allowed_repository_ids:,
          ).query_data
        end

        csv = log_timing(step: "Generate export") { Coverage::ExportCsvGenerator.generate(repository_data) }

        storage_service = Export::BlobStorageService.get(scope)
        log_timing(step: "Store export") do
          storage_service.store(token, csv, "coverage")
        end

        export_time_ms = ((Time.now.utc - requested_at) * 1000).round if requested_at
        log_info(
          "Exported coverage data",
          "gh.security_center.export.requested_at": status.requested_at,
          "gh.security_center.export.elapsed_ms": export_time_ms,
          "gh.security_center.export.file_size": csv.bytesize,
          "gh.security_center.export.rows": repository_data.size,
        )
        GitHub.dogstats.distribution(
          "security_center.export.time",
          export_time_ms,
          tags: [
            "scope:organization",
            "feature:coverage",
            "storage_service:#{storage_service.class.name}"
          ],
        )
        GitHub.dogstats.distribution(
          "security_center.export.bytes",
          csv.bytesize,
          tags: [
            "scope:#{scope.is_a?(Organization) ? "organization" : "business"}",
            "feature:coverage",
          ],
        )
      end
    rescue SecurityCenter::Export::DataQuery::DataLimitExceededError => e
      status&.error!(e.message)
      GitHub.dogstats.increment("security_center.export.data_limit_exceeded", tags: ["scope:organization", "feature:coverage"])
      log_warn("Coverage export hit the maximum number of allowed repositories")
    rescue => e # rubocop:todo Lint/GenericRescue
      status&.error!("We couldn't generate your report. Please try again later. If the problem persists, please contact support.")
      raise e
    end

    private

    sig { override.returns(T::Hash[T.any(String, Symbol), T.untyped]) }
    def logging_context
      scope = T.let(arguments.dig(0, :scope), T.any(Organization, Business))
      user = T.let(arguments.dig(0, :user), User)
      query = T.let(arguments.dig(0, :query_string), String)

      context = {
        "enduser.id": user.display_login,
        "gh.enduser.id": user.id,
        "gh.enduser.login": user.display_login,
        "gh.security_center.search.query": query,
      }

      if scope.is_a?(Organization)
        context.merge!(
          "gh.org.id": scope.id,
          "gh.org.login": scope.display_login,
        )
      else
        context.merge!(
          "gh.business.id": scope.id,
          "gh.business.slug": scope.slug,
        )
      end

      super.merge(context)
    end

    sig { override.returns(T::Hash[T.any(String, Symbol), T.untyped]) }
    def failbot_context
      super.merge({ app: "github-security-center" }).merge(logging_context)
    end
  end
end
