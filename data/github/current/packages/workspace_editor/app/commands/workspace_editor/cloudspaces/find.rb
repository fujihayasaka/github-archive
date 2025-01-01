# typed: true
# frozen_string_literal: true

module WorkspaceEditor
  module Cloudspaces
    class Find < CloudEnvironments::Command

      class Result
        include GitHub::Memoizer

        sig { params(workspace_editor_cloudspace: WorkspaceEditor::Cloudspace).returns(WorkspaceEditor::Cloudspace) }
        attr_writer :workspace_editor_cloudspace

        sig { params(env: Codespaces::Environment).returns(Codespaces::Environment) }
        attr_writer :env

        sig { returns(T.nilable(WorkspaceEditor::Cloudspace)) }
        attr_reader :workspace_editor_cloudspace

        sig { returns(T.nilable(Codespaces::Environment)) }
        attr_reader :env
      end

      include ActiveModel::Validations

      # Usage validations
      validate :workspace_editor_allowed
      validate :enforce_per_user_limit, if: [:connect?, :cloud_environment]

      attr_reader :owner, :repository_id, :pull_request_number, :result, :entry_point

      sig do
        params(
          owner: ::User,
          repository_id: Integer,
          pull_request_number: Integer,
          vscs_target: T.nilable(String),
          concurrency_policy: T.nilable(T.class_of(CloudEnvironments::IConcurrencyLimiter)),
          entry_point: T.nilable(String),
          connect: T::Boolean,
        ).void
      end
      def initialize(
          owner:,
          repository_id:,
          pull_request_number:,
          vscs_target: nil,
          concurrency_policy: nil,
          entry_point: nil,
          connect: false
        )
        @owner = owner
        @repository_id = repository_id
        @pull_request_number = pull_request_number
        @vscs_target = vscs_target
        @result = Result.new
        @concurrency_policy = concurrency_policy
        @entry_point = entry_point
        @connect = connect
      end

      sig { override.returns(Result) }
      def perform
        # We likely want some rate limiting but the regular one is currently implemented as a module that we include
        # so we'd either need a new module to include here or make it an object we can use instead.
        # with_rate_limiting(@attributes[:owner]) do
        validate!

        if cloud_environment
          @result.workspace_editor_cloudspace = WorkspaceEditor::Cloudspace.new(cloud_environment)
          env = fetch_environment! if connect?
          if env.present? && !env.empty?
            @result.env = ::Codespaces::Environment.from_json(env)
          elsif cloud_environment.environment_data.present?
            @result.env = cloud_environment.environment_data
          end
        end
        @result
      end

      private

      memoize def vscs_target
        @vscs_target.present? ? @vscs_target.to_sym : Codespaces::Vscs.default_target
      end

      memoize def cloud_environment
        pull_request = PullRequests::PullRequestAccessor.new.by_number(repository_id: repository_id, number: pull_request_number)
        owner.codespaces.visible_to_workspace_editor_cloud_environments(owner, repository: repository).where(
          repository_id: repository_id,
          pull_request_id: pull_request.id,
          vscs_target: vscs_target,
          state: %w(pending provisioning provisioned),
        ).first
      end

      def connect?
        !!@connect
      end

      def fetch_environment!
        return unless cloud_environment&.guid
        Codespaces::VscsClient.for_codespace(cloud_environment).fetch_environment!(cloud_environment.guid)
      rescue Codespaces::Client::BadResponseError => e
        # If there is an error fetching from the service we will just ignore it and return the cached data.
        # Client side polling will eventually get the connection data.
        nil
      end

      def billable_owner
        cloud_environment&.billable_owner
      end

      def concurrency_policy
        # TODO: Create and use a WorkspaceEditorCloudEnvironment concurrency policy here.
      end

      def enforce_per_user_limit
        # TODO: WorkspaceEditorCloudEnvironment specific logic here
      end

      def workspace_editor_allowed
        raise FeatureDisabledError, "You do not have access to this feature." unless owner && owner.workspace_editor_preview_enabled?(repository: repository)
      end

      def pull_request
        return @pull_request if defined?(@pull_request)

        @pull_request = PullRequests::PullRequestAccessor.new.by_number(repository_id: repository_id, number: pull_request_number)
      end

      def repository
        return @repository if defined?(@repository)

        @repository = pull_request&.head_repository
      end

      sig { returns(CloudEnvironments::IStatsTagger) }
      def stats_tagger
        @stats_tagger ||= Cloudspaces::StatsTagger.new(
          location: cloud_environment&.location,
          repository: repository_id,
          pull_request: pull_request_number,
          vscs_target: vscs_target,
          sku_name: cloud_environment&.sku_name,
          from_pr: true,
          from_fork: cloud_environment&.repository&.fork?,
          repo_empty: cloud_environment&.repository&.empty?,
          owner: owner,
          use_prebuild: Codespaces::Prebuilds.configured?(cloud_environment&.repository),
          is_workspace_editor_cloud_environment: true,
        )
      end
    end
  end
end
