# typed: strict
# frozen_string_literal: true

module DependencyGraph
  class Sbomer
    sig { params(repository: Repository, ghes: T::Boolean).void }
    def initialize(repository, ghes: false)
      @repository = repository
      @ghes = ghes
    end

    sig { returns(DependencyGraph::SBOM::SBOMFile) }
    def get_sbom
      if ghes # call DG-API
        response = repository_sbom_client.get_repository_sbom(
          repository_id: repository.id,
          # As of writing, SHA is not used by DG-API
          sha: repository.default_oid,
          repository_name: repository.name_with_display_owner,
          repository_license: repository.license&.spdx_id,
        )

        # This is a pretty weird case: if we get a successful message from the dependency graph API,
        # but the SBOM is nil or an empty string, we failed somewhere but it's not clear why.
        if response.payload.nil? || response.payload.empty?
          raise DependencyGraph::SBOM::SBOMRequestError, "Failed to generate SBOM."
        end

        sbom = DependencyGraph::SBOM::SBOMFile.new(
          filename: "#{repository.name}_#{repository.owner}_#{repository.default_oid}.json",
          contents: response.payload
        )
      else # otherwise DGP is the gateway
        response = dgp_sbom_client.get_sbom(repository_id: repository.id)

        if response.sbom_contents.empty?
          raise DependencyGraph::SBOM::SBOMRequestError, "Failed to generate SBOM."
        end

        sbom = DependencyGraph::SBOM::SBOMFile.new(
          filename: response.sbom_file_name,
          contents: response.sbom_contents
        )
      end
    rescue DependencyGraphPlatform::Twirp::BaseError, DependencyGraph::BaseTwirpClient::Error => e
      raise DependencyGraph::SBOM::SBOMRequestError, "Failed to generate SBOM: #{e.message}"
    rescue Faraday::TimeoutError
      raise DependencyGraph::SBOM::SBOMTimeoutError, "Could not generate SBOM in time. Please try again."
    end

    sig { returns(String) }
    def create_sbom
      response = dgp_sbom_client.create_sbom(repository_id: repository.id)

      raise DependencyGraph::SBOM::SBOMRequestError, "Failed to create SBOM: no UUID returned." if response.sbom_uuid.blank?

      response.sbom_uuid
    rescue DependencyGraphPlatform::Twirp::BaseError => e
      raise DependencyGraph::SBOM::SBOMRequestError, "Failed to create SBOM: #{e.message}"
    rescue Faraday::TimeoutError
      raise DependencyGraph::SBOM::SBOMTimeoutError, "Could not create SBOM in time. Please try again."
    end

    sig { params(sbom_uuid: String, signed_link_ttl_minutes: Integer).returns(DependencyGraph::SBOM::SBOMResult) }
    def get_sbom_result(sbom_uuid:, signed_link_ttl_minutes: DependencyGraphPlatform::Twirp::SbomClient::DEFAULT_SIGNED_LINK_TTL_MINUTES)
      response = dgp_sbom_client.get_sbom_result(sbom_uuid:, repository_id: repository.id, signed_link_ttl_minutes:)

      if response.repository_id == 0
        raise DependencyGraph::SBOM::SBOMNotFoundError, "Failed to fetch SBOM result: SBOM uuid not found or has expired."
      end

      if response.repository_id != repository.id
        raise DependencyGraph::SBOM::SBOMRequestError, "Failed to fetch SBOM result: repository ID mismatch."
      end

      if response.status == :JOB_STATUS_COMPLETED && response.sbom_url.blank?
        raise DependencyGraph::SBOM::SBOMRequestError, "SBOM generation completed but no download URL was returned."
      end

      DependencyGraph::SBOM::SBOMResult.new(
        status: T.cast(response.status, Symbol),
        sbom_url: response.sbom_url.presence,
        deadline: response.has_deadline? ? T.must(response.deadline).to_time : nil,
        user_error_message: response.user_error_message.presence,
      )
    rescue DependencyGraphPlatform::Twirp::BaseError => e
      raise DependencyGraph::SBOM::SBOMRequestError, "Failed to fetch SBOM result: #{e.message}"
    rescue Faraday::TimeoutError
      raise DependencyGraph::SBOM::SBOMTimeoutError, "Could not fetch SBOM result in time. Please try again."
    end

    sig { params(sbom_uuid: String).returns(DependencyGraph::SBOM::SBOMResult) }
    def poll_sbom_result(sbom_uuid:)
      response = dgp_sbom_client.poll_sbom_result(sbom_uuid:, repository_id: repository.id)

      if response.repository_id == 0
        raise DependencyGraph::SBOM::SBOMNotFoundError, "Failed to poll SBOM result: SBOM uuid not found or has expired."
      end

      if response.repository_id != repository.id
        raise DependencyGraph::SBOM::SBOMRequestError, "Failed to poll SBOM result: repository ID mismatch."
      end

      DependencyGraph::SBOM::SBOMResult.new(
        status: T.cast(response.status, Symbol),
        sbom_url: nil,
        deadline: response.has_deadline? ? T.must(response.deadline).to_time : nil,
        user_error_message: response.user_error_message.presence,
      )
    rescue DependencyGraphPlatform::Twirp::BaseError => e
      raise DependencyGraph::SBOM::SBOMRequestError, "Failed to poll SBOM result: #{e.message}"
    rescue Faraday::TimeoutError
      raise DependencyGraph::SBOM::SBOMTimeoutError, "Could not poll SBOM result in time. Please try again."
    end

    private

    sig { returns(Repository) }
    attr_reader :repository

    sig { returns(T::Boolean) }
    attr_reader :ghes

    sig { returns(DependencyGraph::RepositorySBOMClient) }
    def repository_sbom_client
      # Set the timeout to the default request timeout - 2 to allow for error handling to take place
      @repository_sbom_client ||= T.let(DependencyGraph::RepositorySBOMClient.new(
        request_timeout_seconds: GitHub.default_request_timeout - 2,
        # Disable retries based on timeout exceptions (which is the default)
        retry_options: { exceptions: [] }
      ), T.nilable(DependencyGraph::RepositorySBOMClient))
    end

    sig { returns(DependencyGraphPlatform::Twirp::SbomClient) }
    def dgp_sbom_client
      @dgp_sbom_client ||= T.let(DependencyGraphPlatform::Twirp::SbomClient.new, T.nilable(DependencyGraphPlatform::Twirp::SbomClient))
    end
  end
end
