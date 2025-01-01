# typed: true
# frozen_string_literal: true

module Codespaces
  class PublishToRepository < Command
    class Result
      attr_reader :success, :reason, :repository

      def initialize(success, repository:, reason:)
        @success = success
        @reason = reason
        @repository = repository
      end

      def success?
        @success
      end
    end

    attr_reader :codespace

    def initialize(name:, is_private:, codespace:)
      @name = name
      @is_private = is_private
      @codespace = codespace
    end

    def perform
      user = codespace.owner
      unless codespace.unpublished?
        return Result.new(false, repository: nil, reason: "Codespace must be created from a template repository")
      end

      attributes = {
        name: @name,
        public: !@is_private,
      }

      result = Repository.handle_creation(
        user,
        user.login, # rubocop:disable GitHub/DoNotAllowLogin
        attributes,
      )

      if !result.success?
        return Result.new(false, repository: nil, reason: "#{result.error_message} #{result.repository.errors.full_messages.join('. ')}".strip)
      end

      repository = result.repository

      # Track repos published via codespaces from the template like any other template clone.
      repository_clone = RepositoryClone.new(
        template_repository_id: codespace.repository_id,
        clone_repository: repository,
        state: :finished,
        cloning_user_id: user.id,
      )
      if !repository_clone.save
        return Result.new(false, repository: nil, reason: "#{repository_clone.errors.full_messages.join('. ')}".strip)
      end

      Codespaces::SwitchRepository.call(codespace, repository)

      # If we're coming from a spark, persist the repository association on the workbench too so that we don't lose
      # it when we destroy the ephemeral backing codespace.
      workbench = Spark::Workbench.for_uuid_string(user.id, codespace.spark_workbench_id) if codespace.spark_workbench_id
      if workbench
        workbench.repository_id = repository.id
        if !workbench.save
          return Result.new(false, repository: nil, reason: "#{workbench.errors.full_messages.join('. ')}".strip)
        end
      end

      installation_update_results = Codespace.active_installations_for([codespace.id]).map do |installation|
        SiteScopedIntegrationInstallation::Editors::Repository.grant(
          installation, repositories: [repository], entry_point: :codespaces_command_publish_to_repository
        )
      end

      if installation_update_results.any?(&:failed?)
        Result.new(false, repository: nil, reason: installation_update_results.first&.reason)
      else
        GlobalInstrumenter.instrument("codespaces.published", codespace: codespace)
        Result.new(true, repository: repository, reason: nil)
      end
    end
  end
end
