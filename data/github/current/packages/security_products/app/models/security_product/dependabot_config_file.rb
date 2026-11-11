# typed: true
# frozen_string_literal: true

module SecurityProduct
  class DependabotConfigFile < Service
    DISABLED_KEY = "dependabot.config_file.disabled"
    ENABLED_KEY  = "dependabot.config_file.enabled"

    def enabled?
      log_timing do
        return true unless repository.fork?

        repository.config.enabled?(ENABLED_KEY)
      end
    end

    def disabled?
      !enabled?
    end

    def on_enable(actor:, options:)
      log_timing do
        return Result.new(ToggledServiceCollection.create(to_sym, options)) if repository.deleted?
        return Result.new(ToggledServiceCollection.create(to_sym, options)) unless repository.fork?

        set_enabled_flags(actor: actor)

        Dependabot::RepositoryForkConfigFileEnabledJob.enqueue(repository: repository)

        Result.new(ToggledServiceCollection.create(to_sym, options))
      end
    end

    def on_disable(actor:, options:)
      log_timing do
        return Result.new(ToggledServiceCollection.create(to_sym, options)) unless repository.fork?

        set_disabled_flags(actor: actor)

        Dependabot::RepositoryForkConfigFileDisabledJob.enqueue(repository: repository)

        Result.new(ToggledServiceCollection.create(to_sym, options))
      end
    end

    def to_sym
      :dependabot_config_file
    end

    def self.name
      "Dependabot config file"
    end

    # after_fork_enable is called async by RepositoryForkEnabledJob after enablement of a fork repo. This allows
    # us to perform tasks that should happen outside of the enablement database transaction.
    def self.after_fork_enable(repository:)
      if repository.dependabot_installed?
        Dependabot::Twirp.update_configs_client.resync_config_file(
          repository_id: repository.id,
          owner_id: repository.owner_id,
        )
      else
        install_dependabot(repository)
      end
    end

    # after_fork_disable is called async by RepositoryForkDisabledJob after disablement of a fork repo. This allows
    # us to perform tasks that should happen outside of the enablement database transaction.
    def self.after_fork_disable(repository:)
      # Dependabot should have been installed by the enablement step, in the event it somehow hasn't
      # we skip contacting the Dependabot API service since clearing the enabled flag will
      # permit the user to re-enable and therefore reinstall.
      if repository.dependabot_installed?
        Dependabot::Twirp.update_configs_client.deactivate_update_configs(repository_id: repository.id)
      end
    end

    private

    private_class_method def self.install_dependabot(repository)
      return :installed if repository.dependabot_installed?

      AutomaticAppInstallation.trigger(
        type: :button_clicked,
        originator: GitHub.dependabot_github_app,
        actor: repository,
      )
    end

    def set_enabled_flags(actor:)
      repository.config.enable(ENABLED_KEY, actor)

      GlobalInstrumenter.instrument(ENABLED_KEY, instrumentation_payload(actor))
      true
    end

    def set_disabled_flags(actor:)
      repository.config.delete(ENABLED_KEY, actor)

      GlobalInstrumenter.instrument(DISABLED_KEY, instrumentation_payload(actor))
      true
    end

    def instrumentation_payload(actor)
      payload = {
        user: actor,
        repository: repository,
      }

      if repository.in_organization?
        payload[:org] = repository.organization
      end

      payload
    end
  end
end
