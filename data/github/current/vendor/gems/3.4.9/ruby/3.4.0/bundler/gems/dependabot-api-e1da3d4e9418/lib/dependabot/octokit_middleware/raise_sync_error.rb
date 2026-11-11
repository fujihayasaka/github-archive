# frozen_string_literal: true

require "octokit"

# Isolates specific 403 error subtype returned by GitHub that indicate a Repository is out of sync in Dependabot API.
module Dependabot
  class SyncError < Octokit::ClientError; end

  class ResourceUnavailableToInstallation < SyncError; end

  class RepositoryArchived < SyncError; end

  module OctokitMiddleware
    class RaiseSyncError < Faraday::Middleware
      def on_complete(response)
        status  = response[:status].to_i
        body    = response[:body].to_s

        # We currently only isolate specific 403 responses.
        return unless status == 403

        raise ResourceUnavailableToInstallation, response if not_accessible_by_integration?(body)
        raise RepositoryArchived, response if archived_repository?(body)
      end

      private

      # Occurs when an integration attempts to access a resource it does not have access to via either a User
      # or Bot request.
      #
      # This generally happens when a Repository has been transferred to a new owner but we are in the process
      # of attempting access using the previous owner's Dependabot installation id.
      #
      # See: https://github.com/github/github/blob/master/lib/platform/authorization/integration_authorizer.rb
      def not_accessible_by_integration?(body)
        body =~ /Resource not accessible by integration/i
      end

      def archived_repository?(body)
        body =~ /Repository was archived so is read-only/i
      end
    end
  end
end
