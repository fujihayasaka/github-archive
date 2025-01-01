# typed: strict
# frozen_string_literal: true

module Releases
  class ImmutableRepositoryConfig
    extend T::Helpers
    include Instrumentation::Model

    ENABLED_KEY = "immutable_releases"
    ENFORCED_KEY = Releases::ImmutableOrganizationConfig::ENFORCED_KEY

    sig { returns(Repositories::IRepository) }
    attr_reader :repository

    sig { params(repository: Repositories::IRepository).void }
    def initialize(repository)
      @repository = repository
    end

    # Enable immutable releases for the repository.
    sig { params(actor: User).void }
    def enable_immutable_releases(actor:)
      old_value = immutable_releases_enabled?
      config.enable!(ENABLED_KEY, actor)

      if old_value == false
        instrument_change "immutable_releases_settings_enabled",
        actor: actor
      end
    end

    # Disable immutable releases for the repository.
    sig { params(actor: User).void }
    def disable_immutable_releases(actor:)
      old_value = immutable_releases_enabled?
      config.disable!(ENABLED_KEY, actor)

      if old_value == true
        instrument_change "immutable_releases_settings_disabled",
        actor: actor
      end
    end

    # Checks whether immutable releases are enabled for the repository.
    # Looks to see if any of the following are true:
    # - the repository has immutable releases enabled
    # - the repository owner has enforced immutable releases for this repository
    # - the repository owner has immutable releases enabled for ALL repositories
    sig { returns(T::Boolean) }
    def immutable_releases_enabled?
      config.enabled?(ENABLED_KEY) || immutable_releases_enforced_by_owner?
    end

    # Checks whether immutable releases are enforced by the repository owner.
    # Can be used to distinguish between immutability enabled at the repo level
    # and immutability enforced by the owner.
    sig { returns(T::Boolean) }
    def immutable_releases_enforced_by_owner?
      (org_config.immutable_releases_enabled_for_selected? && config.enabled?(ENFORCED_KEY)) || org_config.immutable_releases_enabled_for_all?
    end

    private

    # Leverage the repository's cached config.
    sig { returns(Configuration) }
    def config
      T.cast(repository, Repository).config # rubocop:disable GitHub/AvoidCast
    end

    sig { returns(Releases::ImmutableOrganizationConfig) }
    def org_config
      Releases::ImmutableOrganizationConfig.new(T.must(repository.owner))
    end

    sig { params(action: String, args: T.untyped).void }
    def instrument_change(action, **args)
      T.cast(@repository, Repository).instrument(action, **args) # rubocop:disable GitHub/AvoidCast
    end
  end
end
