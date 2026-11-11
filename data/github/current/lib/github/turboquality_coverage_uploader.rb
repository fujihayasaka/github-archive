# typed: true
# frozen_string_literal: true

require "github/turboquality_azure"

module GitHub
  # TurboqualityCoverageUploader is responsible for processing incoming coverage files,
  # uploading them to Azure, and notifying downstream consumers.
  class TurboqualityCoverageUploader
    def initialize
      @azure = GitHub::TurboqualityAzure.new
    end

    sig { params(repo_id: Integer, params: T::Hash[Symbol, T.untyped], cov: T.untyped).returns(T.nilable(T::Hash[Symbol, String])) }
    def upload_report(repo_id, params, cov)
      return if cov.nil?

      coverage_report_id = params[:coverage_report_id]

      GitHub.logger.info(
        "Starting to upload the coverage report",
        "code.namespace" => "TurboqualityCoverageUploader",
        "code.function" => "upload_report",
        "gh.repo.id" => repo_id,
        "gh.code_coverage.report.id" => coverage_report_id,
        "gh.code_coverage.report.size" => cov.size,
      )

      uri = @azure.upload(cov, generate_upload_path(repo_id, coverage_report_id), payload_type: "coverage")

      GitHub.logger.info(
        "Sending new coverage report message to Hydro",
        "code.namespace" => "TurboqualityCoverageUploader",
        "code.function" => "upload_report",
        "gh.repo.id" => repo_id,
        "gh.code_coverage.report.uri" => uri,
      )
      send_hydro_msg(repo_id, params, uri)
      GitHub.logger.info(
        "Finished sending new coverage report message to Hydro",
        "code.namespace" => "TurboqualityCoverageUploader",
        "code.function" => "upload_report",
        "gh.repo.id" => repo_id,
        "gh.code_coverage.report.uri" => uri,
      )

      { id: coverage_report_id }
    end

    sig { params(repo_id: Integer, guid: String).returns(String) }
    def generate_upload_path(repo_id, guid)
      "coverage/#{repo_id}/#{guid}.xml.gz"
    end

    sig { params(repo_id: Integer, params: T::Hash[T.any(Symbol, String), T.untyped], uri: String).void }
    def send_hydro_msg(repo_id, params, uri)
      GitHub.dogstats.increment("turboquality_client.upload_coverage_report")
      GitHub.sync_hydro_publisher.publish(
        {
          repository_id: repo_id,
          coverage_uri: uri,
          coverage_id: params[:coverage_report_id],
          commit_oid: params[:commit_oid],
          pr_number: params[:pr_number],
          language_name: params[:language_name],
          label: params[:label],
          branch_name: params[:branch_name],
          base_branch_name: params[:base_branch_name],
        },
        schema: "turboquality.v0.NewCoverageReport",
        topic: "turboquality.v0.NewCoverageReport",
        partition_key: repo_id
      )
    end
  end
end
