# typed: true
# frozen_string_literal: true

module Codespaces
  class CleanUpEnvironment < Command
    class CodespaceFoundError < StandardError; end

    def initialize(
        plan_id:,
        codespace_guid:,
        vscs_target:,
        error_reporter: Codespaces::ErrorReporter,
        location: nil
    )
      @error_reporter = error_reporter
      @codespace_guid = codespace_guid
      @error_reporter.push(codespace_plan_id: plan_id, codespace_guid: @codespace_guid)
      @plan = Codespaces::Plan.find(plan_id)
      @vscs_target = vscs_target
      @location = location
    end

    def perform
      prebuild_template = get_prebuild_template_if_exists
      if prebuild_template
        process_prebuild_template_delete(prebuild_template: prebuild_template)
      else # Note that an orphaned prebuild template environment in VSCS may still exist and hit this.
        process_delete
      end
    end

    private

    def client
      @client ||= Codespaces::VscsClient.for_unscoped_deletion_or_suspension(@plan, @vscs_target)
    end

    def prebuild_client
      return nil if @location.nil?
      @prebuild_client ||= Codespaces::VscsClient.for_prebuild(location: @location)
    end

    def get_prebuild_template_if_exists
      return false unless GitHub.flipper[:codespaces_delete_prebuild_templates_in_environment_cleanup].enabled? && @location.present?

      Codespaces::PrebuildTemplate.find_by(guid: @codespace_guid)
    end

    def process_prebuild_template_delete(prebuild_template:)

      # If the environment is a prebuild template, we should delete it through the CodespacesDeletePrebuildTemplate job.
      Codespaces::DeletePrebuildTemplatesJob.perform_later(
        branch: prebuild_template.branch,
        locations: [@location].compact,
        repository_id: prebuild_template.repository_id,
        vscs_target: @vscs_target,
        vscs_target_url: prebuild_template.vscs_target_url,
        devcontainer_path: prebuild_template.devcontainer_path,
        configuration_id: prebuild_template.codespace_prebuild_configuration_id,
      )
    end

    def process_delete
      codespace = Codespace.find_by(guid: @codespace_guid)
      if codespace.nil?
        begin
          client.delete_environment(@codespace_guid)
          GitHub.instrument("codespaces.deprovision_environment",
            plan_id: @plan.id,
            environment_id: @codespace_guid
          )
        rescue Codespaces::VscsClient::BadResponseError => e
          raise e unless e.error_codes.include? Codespaces::VscsClient::PREBUILD_TEMPLATE_DELETION_DISALLOWED_ERROR_CODE

          GitHub.logger.error(
            "Cannot delete environment for prebuild template",
            :exception => e,
            "code.namespace" => "Codespaces::CleanUpEnvironment",
            "code.function" => "process_delete",
            "gh.codespaces.plan.id" => @plan.id,
            "gh.codespaces.guid" => @codespace_guid,
          )
        end
      else
        raise CodespaceFoundError, "Codespace found for: #{@codespace_guid} so unable to delete." unless codespace.deleted?
      end
    end
  end
end
