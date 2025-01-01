# typed: true
# frozen_string_literal: true

require "github/turboquality_azure"

module GitHub
  # TurboqualityUploader is responsible for processing incoming SARIF files,
  # uploading them to Azure, and notifying the Turboquality service.
  class TurboqualityUploader
    def initialize
      @azure = GitHub::TurboqualityAzure.new
    end

    sig { params(repo_id: Integer, params: T::Hash[Symbol, T.untyped], sarif: T.nilable(Turboscan::ValidatedAnalysis)).void }
    def upload_analysis(repo_id, params, sarif)
      return if sarif.nil?

      uri = ""
      sarif_id = params[:sarif_id]

      GitHub.logger.info(
        "Starting to upload the sarif file",
        "code.namespace" => "TurboqualityUploader",
        "code.function" => "upload_analysis",
        "gh.repo.id" => repo_id,
        "gh.code_scanning.tools" => sarif.tool_names,
        "gh.code_scanning.sarif.id" => sarif_id,
        "gh.code_scanning.sarif.size" => sarif.gzip.size,
      )
      uri = @azure.upload(sarif.gzip, generate_upload_path(repo_id, sarif_id))

      GitHub.logger.info(
        "Sending new analysis message to Hydro",
        "code.namespace" => "TurboqualityUploader",
        "code.function" => "upload_analysis",
        "gh.repo.id" => repo_id,
        "gh.code_scanning.sarif.uri" => uri,
      )
      send_hydro_msg(repo_id, params, uri)
      GitHub.logger.info(
        "Finished sending new analysis message to Hydro",
        "code.namespace" => "TurboqualityUploader",
        "code.function" => "upload_analysis",
        "gh.repo.id" => repo_id,
        "gh.code_scanning.sarif.uri" => uri,
      )
      { id: sarif_id }
    end

    sig { params(repo_id: Integer, guid: String).returns(String) }
    def generate_upload_path(repo_id, guid)
      "upload/#{repo_id}/#{guid}.sarif.gz"
    end

    sig { params(repo_id: Integer, params: T::Hash[T.any(Symbol, String), T.untyped], uri: String).void }
    def send_hydro_msg(repo_id, params, uri)
      GitHub.dogstats.increment("turboquality_client.upload_analysis")
      GitHub.sync_hydro_publisher.publish(
        {
          repository_id: repo_id,
          sarif_uri: uri,
          sarif_id: params[:sarif_id],
          commit_oid: params[:commit_oid],
          ref: params[:ref],
        },
        schema: "turboquality.v0.NewAnalysis",
        topic: "turboquality.v0.NewAnalysis",
        partition_key: repo_id
      )
    end
  end
end
