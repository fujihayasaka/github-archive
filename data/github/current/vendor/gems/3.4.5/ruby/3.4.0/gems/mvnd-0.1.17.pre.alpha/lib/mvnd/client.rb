# frozen_string_literal: true

require 'faraday'
require 'json'
require_relative './v1/migration_twirp'
require_relative './hmac_middleware'
require_relative './twirp_error'

module Mvnd
  class Client
    def initialize(host, faraday_options: {}, hmac_key: ENV['MVND_HMAC_KEY'])
      @host = host
      @hmac_key = hmac_key
      @faraday_options = {
        open_timeout: 1,
        timeout: 5,
        params_encoder: Faraday::FlatParamsEncoder
      }.merge(faraday_options)
    end

    def create_resource(resource)
      request = Mvnd::Migrations::Api::V1::CreateResourceRequest.new(resource: resource)
      response = twirp_client.create_resource(request)
      return response.data if response.error.nil?

      raise TwirpError.new(twirp_response: response)
    end

    def store_event(event)
      request = Mvnd::Migrations::Api::V1::StoreEventRequest.new(event: event)
      response = twirp_client.store_event(request)
      return response.data if response.error.nil?

      raise TwirpError.new(twirp_response: response)
    end

    def generate_signed_upload_url(request)
      response = twirp_client.generate_signed_upload_u_r_l(request)
      return response.data if response.error.nil?

      raise TwirpError.new(twirp_response: response)
    end

    def list_migrations(migration_context)
      request = Mvnd::Migrations::Api::V1::ListMigrationsRequest.new(
        migration_context: migration_context
      )
      response = twirp_client.list_migrations(request)
      return response.data if response.error.nil?

      raise TwirpError.new(twirp_response: response)
    end

    def migration_status(migration_context)
      request = Mvnd::Migrations::Api::V1::MigrationStatusRequest.new(
        migration_context: migration_context
      )
      response = twirp_client.migration_status(request)
      return response.data if response.error.nil?

      raise TwirpError.new(twirp_response: response)
    end

    def create_migration(migration_context, target_url, description)
      request = Mvnd::Migrations::Api::V1::CreateMigrationRequest.new(
        migration_context: migration_context,
        target_url: target_url,
        description: description
      )
      response = twirp_client.create_migration(request)
      return response.data if response.error.nil?

      raise TwirpError.new(twirp_response: response)
    end

    def abort_migration(migration_context)
      request = Mvnd::Migrations::Api::V1::AbortMigrationRequest.new(
        migration_context: migration_context
      )
      response = twirp_client.abort_migration(request)
      return response.data if response.error.nil?

      raise TwirpError.new(twirp_response: response)
    end

    def pause_migration(migration_context)
      request = Mvnd::Migrations::Api::V1::PauseMigrationRequest.new(
        migration_context: migration_context
      )
      response = twirp_client.pause_migration(request)
      return response.data if response.error.nil?

      raise TwirpError.new(twirp_response: response)
    end

    def resume_migration(migration_context)
      request = Mvnd::Migrations::Api::V1::ResumeMigrationRequest.new(
        migration_context: migration_context
      )
      response = twirp_client.resume_migration(request)
      return response.data if response.error.nil?

      raise TwirpError.new(twirp_response: response)
    end

    private

    def twirp_client
      @twirp_client ||= Mvnd::Migrations::Api::V1::MigrationClient.new(faraday)
    end

    def faraday
      Faraday.new([@host, 'twirp'].join('/')) do |conn|
        conn.options.merge! @faraday_options
        conn.use Mvnd::Client::HMACMiddleware, @hmac_key
        conn.adapter(Faraday.default_adapter)
      end
    end
  end
end
