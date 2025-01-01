# typed: true
# frozen_string_literal: true

module ProgrammaticActor
  class Grant

    def self.with(actor)
      new(actor)
    end

    def initialize(actor)
      @actor = actor
    end

    def with_target(target)
      return unless target

      # TODO(jpemberthy): make this more accessible, e.g:
      # current_user#programmatic_actor_grant_on(target)
      grantable = if @actor.using_auth_via_integration?
        if (installation = @actor.oauth_access.installation)
          installation
        elsif (installation = GlobalIntegrationInstallation.for_target(@actor.oauth_access.application, target))
          installation
        else
          integration = @actor.oauth_access.application
          integration.installations.with_target(target).first
        end
      elsif @actor.using_auth_via_user_programmatic_access?
        @actor.programmatic_access.grant_for(target)
      elsif @actor.can_have_granular_permissions?
        @actor.ability_delegate
      end

      return unless grantable

      grantable.async_target.then do |grantable_target|
        grantable_target == target ? grantable : nil
      end.sync
    end

    def with_repository(repository)
      if GitHub.flipper[:find_grantable_from_permissions].enabled?
        with_repository_candidate(repository)
      else
        with_repository_control(repository)
      end
    end

    def with_repository_control(repository)
      return unless repository

      grantable = if @actor.using_auth_via_integration?
        if (installation = @actor.oauth_access.installation)
          installation
        elsif (installation = GlobalIntegrationInstallation.for_repository(@actor.oauth_access.application, repository))
          installation
        else
          integration = @actor.oauth_access.application
          integration.installations.with_repository(repository).first
        end
      elsif @actor.using_auth_via_user_programmatic_access?
        repository.async_owner.then do |owner|
          GitHub::PrefillAssociations.prefill_associations(
            [repository],
            [:owner],
            available_records: [owner]
          )
          @actor.programmatic_access.grant_for_repository(repository)
        end.sync
      elsif @actor.can_have_granular_permissions?
        @actor.ability_delegate
      end

      return unless grantable

      grantable.async_target.then do |target|
        repository.async_owner.then do |owner|
          target == owner ? grantable : nil
        end
      end.sync
    end

    def with_repository_candidate(repository)
      return unless repository

      if @actor.using_auth_via_integration?
        if (installation = @actor.oauth_access.installation)
          installation.repository_ids(repository_ids: [repository.id]).any? ? installation : nil
        elsif (installation = GlobalIntegrationInstallation.for_repository(@actor.oauth_access.application, repository))
          installation
        else
          integration = @actor.oauth_access.application
          integration.installations.with_repository(repository).first
        end
      elsif @actor.using_auth_via_user_programmatic_access?
        repository.async_owner.then do |owner|
          GitHub::PrefillAssociations.prefill_associations(
            [repository],
            [:owner],
            available_records: [owner]
          )
          @actor.programmatic_access.grant_for_repository(repository)
        end.sync
      elsif @actor.can_have_granular_permissions?
        @actor.ability_delegate&.repository_ids(repository_ids: [repository.id]).any? ? @actor.ability_delegate : nil
      end
    end
  end
end
