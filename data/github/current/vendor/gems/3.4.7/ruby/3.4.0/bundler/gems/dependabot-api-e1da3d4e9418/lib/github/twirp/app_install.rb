# typed: true
# frozen_string_literal: true

require "twirp"

module GitHub
  module Twirp
    class AppInstall
      extend T::Sig

      class Error < StandardError; end

      RepositoryInstallResponse = Struct.new(:repository_id, :state, :installation_id)

      sig do
        params(
          client: T.any(Twirp::Client, MonolithTwirp::Dependabot::Tokens::V1::AppInstallAPIClient),
          tenant: T.any(Tenant, NullTenant)
        ).void
      end
      def initialize(client:, tenant:)
        @client = client
        @tenant = tenant
      end

      sig do
        params(
          repository_id: Integer,
        ).returns(RepositoryInstallResponse)
      end
      def create_repository_install(repository_id:)
        response = log_timing do
          app_install_api.create_repository_install(
            MonolithTwirp::Dependabot::Tokens::V1::CreateRepositoryInstallRequest.new(
              repository_id:,
              # We currently use JIT installs for Update Graph jobs send by
              # Dependency Graph, so the trigger is hard-coded for now.
              #
              # If you need to perform a JIT install for a different reason you should:
              # - Add it to the InstallTrigger enum in the proto definition
              # - Update the monolith service to map the proto value to an install trigger
              # - Update and parameterise this method to accept a trigger argument
              #
              # Refer to this file in the monolith to find the triggers available:
              # - https://github.com/github/github/blob/master/packages/apps/app/models/integration_install_trigger.rb
              #
              trigger: :INSTALL_TRIGGER_DEPENDENCY_GRAPH_REQUESTED,
            ),
            headers
          )
        end

        log_and_raise_error(response.error) if response.error.present?

        RepositoryInstallResponse.new(
          repository_id: response.data.repository_id,
          state: response.data.state,
          installation_id: response.data.installation_id,
        )
      end

      private

      sig { returns(T::Hash[String, String]) }
      def headers
        return {} unless Dependabot.proxima?
        raise GitHub::Twirp::Error, "Required Proxima tenant not set" if @tenant.slug.blank?

        {
          headers: { "X-GitHub-Tenant" => @tenant.slug },
        }
      end

      def log_timing
        start_time = Time.now.in_time_zone
        response = yield
        duration = Time.now.in_time_zone - start_time

        method_name = caller_locations(1, 1)&.first&.label || "unknown"
        MetricsClient.distribution(
          "twirp.github.app_install.#{method_name}",
          duration,
          tags: { response_code: response&.error&.code || :ok }
        )

        response
      end

      def log_and_raise_error(error)
        Dependabot::Logger.error(
          msg: error.msg,
          error_code: error.code,
          error_metadata: error.meta,
        )

        raise Error, "#{error.msg} - #{error.meta}"
      end

      sig { returns(MonolithTwirp::Dependabot::Tokens::V1::AppInstallAPIClient) }
      def app_install_api
        @app_install_api ||=
          if @client.is_a?(MonolithTwirp::Dependabot::Tokens::V1::AppInstallAPIClient)
            @client
          else
            MonolithTwirp::Dependabot::Tokens::V1::AppInstallAPIClient.new(@client.connection)
          end
      end
    end
  end
end
