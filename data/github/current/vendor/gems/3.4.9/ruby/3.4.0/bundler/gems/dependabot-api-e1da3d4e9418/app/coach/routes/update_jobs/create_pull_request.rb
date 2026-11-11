# frozen_string_literal: true

require "rbnacl"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependency_file_allowlist"
require "renderer"
require "json"

module Routes
  module UpdateJobs
    class CreatePullRequest < Coach::Middleware
      uses Middlewares::EndpointMetrics, route_class: self
      uses Middlewares::Failbot, route_class: self
      uses Middlewares::CheckUpdateJobToken
      uses Middlewares::CheckUpdateJobProcessing
      uses Middlewares::CheckParams,
           "data.dependencies" => { type: Array, required: true },
           "data.updated-dependency-files" => { type: Array, required: true },
           "data.base-commit-sha" => { type: String, required: true },
           "data.commit-message" => { type: String, required: true },
           "data.pr-title" => { type: String, required: true },
           "data.pr-body" => { type: String, required: true }

      requires :update_job

      def call
        # Security: Never allow updating Actions workflow files outside of the github_actions ecosystem.
        # This was added as a fix to prevent any potential security issues raised in the below issue.
        # https://github.com/github/dependabot-updates/issues/5840#issuecomment-2187039582
        return handle_invalid_dependency_files if invalid_dependency_files?

        pending_pr = create_pending_pull_request
        Dependabot::Logger.info(
          "code.namespace": "Routes::UpdateJobs::CreatePullRequest",
          msg: "Created pending PR",
          **pending_pr.telemetry_attributes,
        )

        update_job.increment_metric(
          "create_pull_request.pending_pr_created",
          tags: { grouped_update: dependency_group_name.present? }
        )

        update_job.update!(base_commit_sha: params[:data][:"base-commit-sha"])

        return Renderer.no_content if multi_ecosystem_update_job? && multi_ecosystems_enabled?

        PrioritizedJobs::CreatePullRequestOnGitHub.perform_later(pending_pr: pending_pr)
        Renderer.no_content
      end

      private

      def multi_ecosystems_enabled?
        update_job.config_feature_enabled?(:multi_ecosystems)
      end

      def multi_ecosystem_update_job?
        update_job.multi_ecosystem_config_id.present?
      end

      def invalid_dependency_files?
        allowlist = DependencyFileAllowlist.new(update_job)
        dependency_files.any? do |file|
          if file["name"].start_with?(".github/workflows/") &&
             update_job.package_manager != PackageManagers::GITHUB_ACTIONS
            true
          else
            !allowlist.allowed?(file["name"])
          end
        end
      end

      def handle_invalid_dependency_files
        Dependabot::Logger.info(
          "code.namespace": "Routes::UpdateJobs::CreatePullRequest",
          msg: "Updating GitHub Actions workflow files is only allowed within the github_actions ecosystem",
          "gh.repo.id": update_job.repo.github_id,
          "gh.owner.id": update_job.repo.account.github_id,
        )

        Renderer.render_error(
          status: 400,
          title: "Bad Request",
          detail: "The request contains invalid or unauthorized changes"
        )
      end

      def create_pending_pull_request # rubocop:disable Metrics/MethodLength
        pr_count =
          update_job.pending_pull_requests.order(:sort_key).last&.sort_key || 0

        pending_pr =
          PendingPullRequest.create!(
            update_job: update_job,
            updated_dependency_details: updated_dependencies.map(&:to_h),
            sort_key: pr_count + 1,
            grouped_update: dependency_group_name.present?,
            dependency_group: dependency_group
          )

        pending_pr.message_data = message_data

        pending_pr.encrypted_dependency_files_blob.attach(
          io: StringIO.new(encrypt_dependency_files_blob),
          filename: pending_pr.id,
          content_type: "application/octet-stream",
          identify: false,
        )

        pending_pr
      rescue ActiveRecord::RecordNotUnique => e
        raise unless e.message.include?("pending_pull_requests_parent_sort")

        retry
      end

      def message_data
        {
          commit_message: params[:data][:"commit-message"],
          pr_title: params[:data][:"pr-title"],
          pr_body: params[:data][:"pr-body"],
        }
      end

      def encrypt_dependency_files_blob
        encrypt(dependency_files.to_json)
      end

      def encrypt(json)
        token = Base64.strict_decode64(Prius.get(:temporary_file_encryption_key))
        encrypted_box = RbNaCl::SimpleBox.from_secret_key(token)

        Base64.strict_encode64(encrypted_box.encrypt(json))
      end

      def updated_dependencies
        params[:data][:dependencies].map do |dep|
          Dependabot::Dependency.new(
            name: dep.fetch(:name),
            version: dep.fetch(:version, nil),
            previous_version: dep.fetch(:"previous-version"),
            requirements: dep.fetch(:requirements),
            previous_requirements: dep.fetch(:"previous-requirements"),
            package_manager: update_job.package_manager,
            directory: dep.fetch(:directory, nil),
            removed: dep.fetch(:removed, false)
          )
        end
      end

      def dependency_files
        encoding = Dependabot::DependencyFile::ContentEncoding::UTF_8
        params[:data][:"updated-dependency-files"].map do |file_data|
          dep = Dependabot::DependencyFile.new(
            name: file_data.fetch(:name),
            content: file_data.fetch(:content),
            directory: file_data.fetch(:directory),
            type: file_data.fetch(:type),
            deleted: file_data.fetch(:deleted, false),
            content_encoding: file_data.fetch(:content_encoding, encoding),
            symlink_target: file_data.fetch(:symlink_target, nil),
          )
          dep.mode = file_data.fetch(:mode, nil)
          dep.to_h
        end
      end

      def dependency_group_name
        params[:data].dig(:"dependency-group", :name)
      end

      def dependency_group
        return nil if dependency_group_name.blank?

        # NOTE: `#find_by` will return `nil`
        update_job.update_config.dependency_groups.find_by(name: dependency_group_name)
      end
    end
  end
end
