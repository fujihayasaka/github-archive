# typed: true
# frozen_string_literal: true

module Codespaces
  class CreatePrebuildTemplate < Command

    class Error < Codespaces::Error; end
    class InvalidPrebuildTemplate < Codespaces::CreatePrebuildTemplate::Error; end
    class FeatureNotSupported < Codespaces::CreatePrebuildTemplate::Error; end

    attr_accessor :repository,
                  :location,
                  :vscs_target,
                  :vscs_target_url,
                  :environment_options,
                  :oid,
                  :branch,
                  :workflow_run_id,
                  :configuration_id

    def initialize(
        repository:,
        vscs_target: Codespaces::Vscs.default_target,
        vscs_target_url: nil,
        environment_options: {},
        location:,
        oid:,
        branch:,
        workflow_run_id:,
        configuration_id: nil
      )
      @repository = repository
      @location = location
      @vscs_target = vscs_target.to_sym
      @vscs_target_url = vscs_target_url
      @environment_options = environment_options
      @oid = oid
      @branch = branch
      @workflow_run_id = workflow_run_id
      @configuration_id = configuration_id
    end

    def perform
      validate!

      template = PrebuildTemplate.new(
        state: :pending,
        branch: branch,
        location: location,
        oid: oid,
        repository: repository,
        vscs_target: vscs_target,
        vscs_target_url: vscs_target_url,
        prebuild_hash: prebuild_hash,
        devcontainer_path: environment_options["devcontainer_path"],
        codespace_prebuild_configuration_id: configuration_id,
      )

      if GitHub.flipper[:codespaces_prebuild_template_plan_backfill].enabled?(repository&.owner)
        plan = Codespaces::Plan.for(location: location, vscs_target: vscs_target)
        template.plan_id = plan&.id
      end

      if !template.valid?
        raise InvalidPrebuildTemplate, "Invalid prebuild template: #{template.errors.full_messages.join(', ')}"
      end

      begin
        response = client(plan:).create_prebuild_template(
          location: template.location,
          environment_options: environment_options,
          name: template.name,
          repo: repository,
          prebuild_hash: template.prebuild_hash,
          moniker: template.moniker,
          workflow_run_id: workflow_run_id,
          configuration_id: configuration_id,
        )

        template.guid = response["templateId"]
        template.save!
        storage_sas_url = response["sasUrl"]

        GitHub.logger.info(
          "Codespaces Prebuild Create Template successfully completed",
          "gh.repo.id" => repository.id,
          "gh.repo.owner.login" => repository.owner.display_login,
          "gh.codespaces.prebuilds.configuration.id" => configuration_id,
          "gh.codespaces.prebuild_hash" => prebuild_hash,
          "gh.codespaces.prebuild.workflow_run_id" => workflow_run_id,
          "gh.codespaces.location" => location,
          "gh.codespaces.vscs_target" => vscs_target,
          "code.namespace" => "Codespaces::CreatePrebuildTemplate",
        )

        [template, storage_sas_url]
      rescue ArgumentError => e
        raise InvalidPrebuildTemplate, "Invalid prebuild template: #{e.message}"
      end
    end

    private

    def validate!
      unless Codespaces::Prebuilds.configured?(repository)
        raise FeatureNotSupported, "Prebuilds are not configured for this repository"
      end

      Codespaces::ValidatePrebuildAccess.call(repository: repository, vscs_target: vscs_target, vscs_target_url: vscs_target_url)
    end

    def client(plan: nil)
      Codespaces::VscsClient.for_prebuild(
        location: location,
        vscs_target: vscs_target,
        vscs_target_url: vscs_target_url,
        branch: branch,
        oid: oid,
        plan: plan
      )
    end

    memoize def prebuild_hash
      Codespaces::CalculatePrebuildHash.call(repository: repository, oid: oid, devcontainer_path: environment_options["devcontainer_path"])
    end
  end
end
