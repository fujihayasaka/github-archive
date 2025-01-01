# typed: strict
# frozen_string_literal: true

module Launch
  module Twirp
    class ArtifactsExchangeClient < Launch::Twirp::BaseClient
      sig { params(request: GitHub::Launch::Services::Artifactsexchange::ExchangeURLRequest).returns(TwirpResponse) }
      def exchange_url(request)
        rpc(
          :ExchangeURL,
          request,
        )
      end

      sig { params(unauthenticated_url: T.nilable(String), repository: Repository, resource_type: ResourceType).returns(TwirpResponse) }
      def exchange_url_for(unauthenticated_url:, repository:, resource_type:)
        request = GitHub::Launch::Services::Artifactsexchange::ExchangeURLRequest.new({
          unauthenticated_url: unauthenticated_url.to_s,
          repository_id: identity(repository),
          resource_type: resource_type.value,
        })

        exchange_url(request)
      end

      sig do
        params(
          repository_global_id: String,
          execution_id: T.nilable(String),
          artifact_name: String
        ).returns(TwirpResponse)
      end
      def delete_artifact(repository_global_id:, execution_id:, artifact_name:)
        request = GitHub::Launch::Services::Artifactsexchange::DeleteArtifactRequest.new(
          repository_id: GitHub::Launch::Pbtypes::GitHub::Identity.new(global_id: repository_global_id),
          execution_id:,
          artifact_name:,
        )

        rescue_rpc { client.delete_artifact(request) }
      end

      sig { params(repository_global_id: String, execution_id: T.nilable(String)).returns(TwirpResponse) }
      def delete_build_logs(repository_global_id:, execution_id:)
        req = GitHub::Launch::Services::Artifactsexchange::DeleteBuildLogsRequest.new(
          repository_id: GitHub::Launch::Pbtypes::GitHub::Identity.new(global_id: repository_global_id),
          execution_id:,
        )

        rescue_rpc { client.delete_build_logs(req) }
      end

      private

      sig { returns(T.class_of(GitHub::Launch::Services::Artifactsexchange::ActionsArtifactExchangeClient)) }
      def twirp_class
        GitHub::Launch::Services::Artifactsexchange::ActionsArtifactExchangeClient
      end
    end

    class ResourceType < T::Enum

      enums do
        COMPLETED_JOB_LOG = new
        COMPLETED_LOG = new
        COMPLETED_RUN_LOG = new
        COMPLETED_STEP_LOG = new
        DOWNLOAD_ARTIFACT = new
        STREAMING_LOG = new
        UNKNOWN = new
      end

      sig { returns(Integer) }
      def value
        case self
        when COMPLETED_JOB_LOG  then GitHub::Launch::Services::Artifactsexchange::ResourceType::TYPE_COMPLETED_JOB_LOG
        when COMPLETED_LOG      then GitHub::Launch::Services::Artifactsexchange::ResourceType::TYPE_COMPLETED_LOG
        when COMPLETED_RUN_LOG  then GitHub::Launch::Services::Artifactsexchange::ResourceType::TYPE_COMPLETED_RUN_LOG
        when COMPLETED_STEP_LOG then GitHub::Launch::Services::Artifactsexchange::ResourceType::TYPE_COMPLETED_STEP_LOG
        when DOWNLOAD_ARTIFACT  then GitHub::Launch::Services::Artifactsexchange::ResourceType::TYPE_DOWNLOAD_ARTIFACT
        when STREAMING_LOG      then GitHub::Launch::Services::Artifactsexchange::ResourceType::TYPE_STREAMING_LOG
        when UNKNOWN            then GitHub::Launch::Services::Artifactsexchange::ResourceType::TYPE_UNKNOWN
        else T.absurd(self)
        end
      end
    end
  end
end
