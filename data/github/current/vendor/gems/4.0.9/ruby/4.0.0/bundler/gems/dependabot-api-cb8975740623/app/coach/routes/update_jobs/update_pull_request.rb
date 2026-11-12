# frozen_string_literal: true

require "rbnacl"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "renderer"

module Routes
  module UpdateJobs
    class UpdatePullRequest < Coach::Middleware
      uses Middlewares::EndpointMetrics, route_class: self
      uses Middlewares::Failbot, route_class: self
      uses Middlewares::CheckUpdateJobToken
      uses Middlewares::CheckUpdateJobProcessing
      uses Middlewares::CheckParams,
           "data.dependency-names" => { type: Array, required: true },
           "data.updated-dependency-files" => { type: Array, required: true },
           "data.base-commit-sha" => { type: String, required: true }

      requires :update_job

      def call # rubocop:disable Metrics/MethodLength
        return wrong_dependency_updated_error if wrong_dependency_updated

        update_job.increment_metric(
          "update_pull_request.initiated",
          tags: { grouped_update: pull_request.grouped_update }
        )

        update_job.update!(base_commit_sha: params[:data][:"base-commit-sha"])

        pending_pull_request_update = PendingPullRequestUpdate.create!(
          pull_request: pull_request,
          updated_base_commit_sha: update_job.base_commit_sha,
        )

        pending_pull_request_update.encrypted_dependency_files_blob.attach(
          io: StringIO.new(encrypted_dependency_files_blob),
          filename: pending_pull_request_update.id,
          content_type: "application/octet-stream",
          identify: false,
        )

        pending_pull_request_update.message_data = message_data if message_data.values.any?(&:present?)

        UpdatePullRequestJob.perform_later(
          update_job_id: update_job.id,
          pending_pull_request_update: pending_pull_request_update,
        )

        Renderer.no_content
      end

      private

      def wrong_dependency_updated
        Set.new(update_job.dependencies) !=
          Set.new(params[:data][:"dependency-names"])
      end

      def wrong_dependency_updated_error
        Renderer.render_error(
          status: 400,
          title: "Bad Request",
          detail: "Updated dependency was not in the list of dependencies " \
                  "requested for this update job",
        )
      end

      def encrypted_dependency_files_blob
        token =
          Base64.strict_decode64(Prius.get(:temporary_file_encryption_key))
        encrypted_box = RbNaCl::SimpleBox.from_secret_key(token)

        Base64.strict_encode64(encrypted_box.encrypt(dependency_files.to_json))
      end

      def dependency_files
        encoding = Dependabot::DependencyFile::ContentEncoding::UTF_8
        params[:data][:"updated-dependency-files"].map do |file_data|
          Dependabot::DependencyFile.new(
            name: file_data.fetch(:name),
            content: file_data.fetch(:content),
            directory: file_data.fetch(:directory),
            type: file_data.fetch(:type),
            deleted: file_data.fetch(:deleted, false),
            content_encoding: file_data.fetch(:content_encoding, encoding),
            symlink_target: file_data.fetch(:symlink_target, nil),
            mode: file_data.fetch(:mode, nil)
          ).to_h
        end
      end

      def message_data
        {
          pr_title: params[:data][:"pr-title"],
          pr_body: params[:data][:"pr-body"],
          commit_message: params[:data][:"commit-message"],
        }
      end

      def pull_request
        @pull_request ||= update_job.pull_request_transition.pull_request
      end
    end
  end
end
