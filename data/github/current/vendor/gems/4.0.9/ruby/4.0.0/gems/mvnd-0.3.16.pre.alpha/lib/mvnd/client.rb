# frozen_string_literal: true

require 'faraday'
require 'json'
require_relative './v1/migration_twirp'
require_relative './hmac_middleware'
require_relative './twirp_error'

module Mvnd
  class Client
    def initialize(faraday)
      @faraday = faraday
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

    def list_migrations(migration_context, page_size: 0, page_token: "")
      request = Mvnd::Migrations::Api::V1::ListMigrationsRequest.new(
        migration_context: migration_context,
        page_size: page_size,
        page_token: page_token
      )
      response = twirp_client.list_migrations(request)
      return response.data if response.error.nil?

      raise TwirpError.new(twirp_response: response)
    end

    def list_migration_nodes(migration_context, repository_nwo, state, origin, page_size, after)
      request = Mvnd::Migrations::Api::V1::ListMigrationNodesRequest.new(
        migration_context: migration_context,
        repository_nwo: repository_nwo,
        state: state,
        origin: origin,
        page_size: page_size,
        after: after
      )
      response = twirp_client.list_migration_nodes(request)
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

    def create_migration(migration_context, target_url, description, repositories)
      request = Mvnd::Migrations::Api::V1::CreateMigrationRequest.new(
        migration_context: migration_context,
        target_url: target_url,
        description: description,
        repositories: repositories
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

    def mark_all_resources_sent(migration_context, repository_nwo)
      request = Mvnd::Migrations::Api::V1::MarkAllResourcesSentRequest.new(
        migration_context: migration_context,
        repository_nwo: repository_nwo
      )
      response = twirp_client.mark_all_resources_sent(request)
      return response.data if response.error.nil?

      raise TwirpError.new(twirp_response: response)
    end

    def mark_repository_locked(migration_context, repository_nwo)
      request = Mvnd::Migrations::Api::V1::MarkRepositoryLockedRequest.new(
        migration_context: migration_context,
        repository_nwo: repository_nwo
      )
      response = twirp_client.mark_repository_locked(request)
      return response.data if response.error.nil?

      raise TwirpError.new(twirp_response: response)
    end

    def update_repository_state(migration_context, repository_nwo, state, destination_nwo: nil)
      request = Mvnd::Migrations::Api::V1::UpdateRepositoryStateRequest.new(
        migration_context: migration_context,
        repository_nwo: repository_nwo,
        state: state,
        destination_nwo: destination_nwo
      )
      response = twirp_client.update_repository_state(request)
      return response.data if response.error.nil?

      raise TwirpError.new(twirp_response: response)
    end

    def report_git_sync(migration_context, repository_nwo, start_time, end_time, git_source, success, error_message, error_messages: [], additional_errors: false)
      request = Mvnd::Migrations::Api::V1::ReportGitSyncRequest.new(
        migration_context: migration_context,
        repository_nwo: repository_nwo,
        iteration_start_time: start_time,
        iteration_end_time: end_time,
        git_source: git_source,
        success: success,
        error_message: error_message,
        error_messages: error_messages,
        additional_errors: additional_errors
      )
      response = twirp_client.report_git_sync(request)
      return response.data if response.error.nil?

      raise TwirpError.new(twirp_response: response)
    end

    private

    def twirp_client
      @twirp_client ||= Mvnd::Migrations::Api::V1::MigrationClient.new(@faraday)
    end
  end
end
