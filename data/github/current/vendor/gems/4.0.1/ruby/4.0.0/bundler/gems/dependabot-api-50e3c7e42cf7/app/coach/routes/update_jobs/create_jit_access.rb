# frozen_string_literal: true

require "renderer"

module Routes
  module UpdateJobs
    class CreateJitAccess < Coach::Middleware
      uses Middlewares::EndpointMetrics, route_class: self
      uses Middlewares::Failbot, route_class: self
      uses Middlewares::CheckUpdateJobToken
      uses Middlewares::CheckUpdateJobProcessing

      requires :update_job

      def call
        return forbidden if cross_org_request?
        return forbidden if github_access_data.blank?

        update_job.update_config.add_jit_accessed_internal_github_repo_ids([github_access_data.repository_id])

        Renderer.render({
          "username" => "x-access-token",
          "password" => github_access_data.token,
        }.to_json)
      rescue Octokit::Forbidden => e
        Dependabot::Logger.info(
          msg: "Could not fetch GitHub access token for update job",
          "code.namespace": self.class.name.to_s,
          "exception.type": e.class,
          "exception.message": e.response_body,
          **update_job.telemetry_attributes,
        )
        forbidden
      end

      private

      def forbidden
        Renderer.render_error(
          status: 403,
          title: "Forbidden",
          detail: "Either the repo doesn't exist, or Dependabot doesn't have access to it",
        )
      end

      # TODO: remove this when cross-repo support is implemented
      def cross_org_request?
        params.fetch(:account).to_s.downcase != update_job.repo.account.github_login.to_s.downcase
      end

      def github_access_data
        return @github_access_data if defined?(@github_access_data)

        @github_access_data = nil

        begin
          @github_access_data = tokens_client.create_jit_access(
            account_name: params.fetch(:account),
            repo_name: params.fetch(:repository)
          )
        rescue GitHub::Twirp::Tokens::Error
          nil
        ensure
          Dependabot::Logger.info(
            msg: "Requesting JIT access token for update job",
            "code.namespace": self.class.name.to_s,
            account_requested: params.fetch(:account),
            success: @github_access_data.present?,
            **update_job.telemetry_attributes,
          )
        end

        @github_access_data
      end

      def tokens_client
        @tokens_client ||=
          GitHub::Twirp::Tokens.new(
            client: Dependabot::Application.github_twirp_client,
            tenant: update_job.repo.account.tenant,
          )
      end
    end
  end
end
