# typed: strict
# frozen_string_literal: true

require "github-orca"

module Orca
  class Client
    class Error < StandardError; end

    class ClientError < Error; end
    class ServerError < Error; end

    TWIRP_CLIENT_ERRORS = T.let([
      :invalid_argument,
      :not_found,
    ].freeze, T::Array[Symbol])


    include GitHub::Memoizer

    sig { params(actor: User).returns(GitHub::Orca::Actor) }
    def self.actor(actor)
      GitHub::Orca::Actor.new(
        id: actor.id,
        login: actor.display_login,
        analytics_tracking_id: actor.analytics_tracking_id
      )
    end

    sig { params(repository: Repository).returns(GitHub::Orca::Repository) }
    def self.repository(repository)
      GitHub::Orca::Repository.new(
        id: repository.id,
        name: repository.name,
        clone_url: repository.clone_url
      )
    end

    sig { params(linguist_language: Linguist::Language).returns(GitHub::Orca::LingustLanguage) }
    def self.language(linguist_language)
      GitHub::Orca::LingustLanguage.new(
          name: linguist_language.name,
          language_id: linguist_language.language_id,
        )
    end

    sig { params(organization: Organization).returns(GitHub::Orca::Organization) }
    def self.organization(organization)
      GitHub::Orca::Organization.new(
        id: organization.id,
        login: organization.display_login,
        analytics_tracking_id: organization.analytics_tracking_id
      )
    end

    sig { params(error: Twirp::Error).returns(T::Boolean) }
    def self.client_error?(error)
      TWIRP_CLIENT_ERRORS.include?(error.code)
    end

    SERVICE_NAME = T.let("orca".freeze, String)

    sig { returns(String) }
    attr_reader :base_url

    sig { returns(String) }
    attr_reader :hmac_key

    sig { params(base_url: String, hmac_key: String).void }
    def initialize(base_url:, hmac_key:)
      @base_url = T.let(base_url, String)
      @hmac_key = T.let(hmac_key, String)
      # Some methods get rate limits when called, so we memoize them here.
      @rate_limits = T.let({}, T::Hash[String, T.nilable(GitHub::Orca::RateLimitDetails)])

      raise ArgumentError, "base_url cannot be empty" if base_url.empty?
      raise ArgumentError, "hmac_key cannot be empty" if hmac_key.empty?
    end

    # Issues a StartCustomization request and returns the pipeline ID.
    sig do
      params(
        actor: User,
        organization: Organization,
        repositories: T::Array[Repository],
        use_private_telemetry: T::Boolean,
        languages: T::Array[Linguist::Language],
      ).returns(String)
    end
    def start_customization(actor:, organization:, repositories:, use_private_telemetry:, languages: [])
      repositories = repositories.sort_by { _1.id }
      languages = languages.map do |lang|
        self.class.language(lang)
      end
      request = GitHub::Orca::StartCustomizationRequest.new(
        dotcom_actor: self.class.actor(actor),
        language_filters: languages,
        organization: self.class.organization(organization),
        repositories: repositories.map { self.class.repository(_1) },
        use_private_telemetry: use_private_telemetry,
      )

      response = orca_api_client.start_customization(request)

      if error = response.error
        if self.class.client_error?(error)
          raise ClientError, error.msg
        end

        raise ServerError, error.msg
      end
      @rate_limits[organization.display_login] = response.data.rate_limit
      response.data.pipeline_id
    end

    sig { params(pipeline_id: String).returns(T.nilable(GitHub::Orca::PipelineDetails)) }
    def get_pipeline_details(pipeline_id:)
      fixture = Rails.env.development? ? look_up_fixture(pipeline_id) : nil
      return fixture if fixture

      request = GitHub::Orca::GetPipelineDetailsRequest.new(
        pipeline_id: pipeline_id
      )

      response = orca_api_client.get_pipeline_details(request)

      if error = response.error
        if error.code == :not_found
          return
        end

        if self.class.client_error?(error)
          raise ClientError, error.msg
        end

        raise ServerError, error.msg
      end

      response.data.pipeline_details
    end

    sig do
      params(organization: Organization)
        .returns(T.nilable(GitHub::Orca::RateLimitDetails))
    end
    def get_rate_limit(organization:)
      if @rate_limits.key?(organization.display_login)
        return @rate_limits[organization.display_login]
      end
      # if we have not yet fetched the rate limit for this organization, we fetch it now
      # there is no direct API to fetch rate limits for an organization, so we fetch the latest
      # pipeline as well as the rate limit details
      request = GitHub::Orca::GetLatestPipelineDetailsRequest.new(
        organization: self.class.organization(organization),
        organization_name: organization.display_login,
        status: GitHub::Orca::PipelineStatus::PIPELINE_STATUS_UNSPECIFIED
      )

      response = orca_api_client.get_latest_pipeline_details(request)

      if error = response.error
        if error.code == :not_found
          return
        end

        if self.class.client_error?(error)
          raise ClientError, error.msg
        end

        raise ServerError, error.msg
      end
      response.data.rate_limit
    end

    sig do
      params(organization: Organization, status: Integer)
        .returns(T.nilable(GitHub::Orca::PipelineDetails))
    end
    def get_latest_pipeline_details(organization:, status: GitHub::Orca::PipelineStatus::PIPELINE_STATUS_UNSPECIFIED)
      request = GitHub::Orca::GetLatestPipelineDetailsRequest.new(
        organization: self.class.organization(organization),
        organization_name: organization.display_login,
        status: status
      )

      response = orca_api_client.get_latest_pipeline_details(request)

      if error = response.error
        if error.code == :not_found
          return
        end

        if self.class.client_error?(error)
          raise ClientError, error.msg
        end

        raise ServerError, error.msg
      end
      @rate_limits[organization.display_login] = response.data.rate_limit
      response.data.pipeline_details
    end

    sig do
      params(organization: Organization, status: Integer)
        .returns(T.nilable(GitHub::Orca::GetPipelinesResponse))
    end
    def get_pipelines(organization:, status: GitHub::Orca::PipelineStatus::PIPELINE_STATUS_UNSPECIFIED)
      request = GitHub::Orca::GetPipelinesRequest.new(
        organization: self.class.organization(organization),
      )

      response = orca_api_client.get_pipelines(request)
      if error = response.error
        if error.code == :not_found
          return
        end

        if self.class.client_error?(error)
          raise ClientError, error.msg
        end

        raise ServerError, error.msg
      end
      response.data
    end

    # Issues a DeleteCustomization request and returns the pipeline ID.
    sig { params(actor: User, organization: Organization, pipeline_id: String).returns(String) }
    def delete_pipeline(actor:, organization:, pipeline_id:)
      request = GitHub::Orca::DeleteCustomizationRequest.new(
        dotcom_actor: self.class.actor(actor),
        organization: self.class.organization(organization),
        pipeline_id: pipeline_id
      )

      response = orca_api_client.delete_customization(request)

      if error = response.error
        if self.class.client_error?(error)
          raise ClientError, error.msg
        end

        raise ServerError, error.msg
      end
      response.data.pipeline_id
    end

    # Issues a CancelCustomization request and returns the pipeline ID.
    sig { params(actor: User, organization: Organization, pipeline_id: String).returns(String) }
    def cancel_pipeline(actor:, organization:, pipeline_id:)
      request = GitHub::Orca::CancelCustomizationRequest.new(
        dotcom_actor: self.class.actor(actor),
        organization: self.class.organization(organization),
        pipeline_id: pipeline_id
      )

      response = orca_api_client.cancel_customization(request)

      if error = response.error
        if self.class.client_error?(error)
          raise ClientError, error.msg
        end

        raise ServerError, error.msg
      end
      response.data.pipeline_id
    end

    private

    sig { returns(GitHub::Orca::OrcaAPIClient) }
    memoize def orca_api_client
      GitHub::Orca::OrcaAPIClient.new(connection)
    end

    sig { returns(GitHub::FaradayClient::Internal) }
    memoize def connection
      ::GitHub::FaradayClient::Internal.new(
        base_url,
        ssl: nil
      ) do |conn|
        conn.options[:open_timeout] = 0.250
        conn.headers[:user_agent] = "github-#{GitHub.role}/#{GitHub.current_sha}"

        conn.request :retry,
          max:                 3,
          interval:            0.050,
          interval_randomness: 0.5,
          backoff_factor:      1.2,
          exceptions:  [Faraday::ConnectionFailed, Faraday::RetriableResponse, Faraday::TimeoutError],
          retry_block: proc { GitHub.dogstats.increment("rest.#{SERVICE_NAME}.retries") }

        conn.use ::GitHub::FaradayMiddleware::Datadog,
          stats: GitHub.dogstats,
          service_name: SERVICE_NAME

        conn.use ::GitHub::FaradayMiddleware::Resilient,
          name: SERVICE_NAME

        conn.use ::GitHub::FaradayMiddleware::HMACAuth,
          hmac_key: hmac_key

        conn.use ::GitHub::FaradayMiddleware::IncreasingTimeout,
          factor: 2

        conn.adapter :typhoeus
      end
    end

    # If using this, you need to modify the fixture's values for
    # pipeline_details.pipeline.organization -- both id and login
    # to match the current organization.
    sig { params(pipeline_id: String).returns(T.nilable(GitHub::Orca::PipelineDetails)) }
    def look_up_fixture(pipeline_id)
      return nil unless Rails.env.development?

      filename = "#{Rails.root}/packages/orca/fixtures/pipelines/#{pipeline_id}.json"
      return unless File.exist?(filename)

      file = File.read(filename)
      response = GitHub::Orca::GetPipelineDetailsResponse.decode_json(file)
      response.pipeline_details
    end
  end
end
