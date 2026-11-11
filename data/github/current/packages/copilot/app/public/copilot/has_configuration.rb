# typed: strict
# frozen_string_literal: true

module Copilot
  Configurable = T.type_alias { T.any(::Business, ::Organization, ::User) } # rubocop:todo Rails/ModuleNaming

  module HasConfiguration
    extend T::Helpers

    abstract!

    include BaseHelpers::Helpers
    include Copilot::Helpers

    sig { overridable.returns(Configurable) }
    def configurable_object
      Kernel.raise NotImplementedError, "Must be implemented by including class"
    end

    sig { void }
    def ensure_configuration!
      configuration
      nil
    end

    sig { abstract.returns(T::Boolean) }
    def copilot_for_business_enabled?; end

    sig { returns(T::Boolean) }
    def has_configuration?
      load_configuration.present?
    end

    sig { returns(Copilot::Configuration) }
    def configuration
      @configuration ||= T.let(real_configuration, T.nilable(Copilot::Configuration))
    end

    private

    sig { returns(Copilot::Configuration) }
    def real_configuration
      # this is on the reading connection, so we'll see if we already have a configuration
      # this would make us extremely happy
      configuration = load_configuration

      # neat-o, we do, let's get out of here
      if configuration.present?
        GitHub.dogstats.increment("copilot.configuration.present", tags: ["connection:reading", "configurable_type:#{configurable_type}"])
        return configuration
      end

      # poopy - we don't, let's try to create one
      GitHub.dogstats.increment("copilot.configuration.missing", tags: ["connection:reading", "configurable_type:#{configurable_type}"])

      with_write do
        Copilot::Configuration.transaction do
          # we need to check again because another thread could have created one
          configuration = Copilot::Configuration.find_by(configurable_id: configurable_object.id, configurable_type: configurable_type)

          # will you look at that, another thread created one!
          if configuration.present?
            GitHub.dogstats.increment("copilot.configuration.present", tags: ["connection:writing", "configurable_type:#{configurable_type}"])
            next configuration
          end

          # nope, we're the first, let's create one
          GitHub.dogstats.increment("copilot.configuration.new_record", tags: ["connection:writing", "configurable_type:#{configurable_type}"])
          config = Copilot::Configuration.create(
            {
              configurable_id: configurable_object.id,
              # Organizations will emit configurable_type of User, so we have to force this
              configurable_type: configurable_type,
            }.reverse_merge(configuration_defaults),
          )

          # we're done here
          config
        end
      end
    end

    sig { returns(String) }
    def configurable_type
      return "Business"     if configurable_object.is_a?(::Business)
      return "Organization" if configurable_object.is_a?(::Organization)
      return "User"         if configurable_object.is_a?(::User)
      Kernel.raise "Unknown configurable type"
    end

    sig { returns(T.nilable(Copilot::Configuration)) }
    def load_configuration
      ActiveRecord::Base.connected_to(role: :reading) do
        # Organizations will emit configurable_type of User, so we have to force this
        Copilot::Configuration.find_by(configurable_id: configurable_object.id, configurable_type: configurable_type)
      end
    end

    sig { returns(Copilot::Configuration) }
    def create_configuration
      ActiveRecord::Base.connected_to(role: :writing) do
        Copilot::Configuration.create(
          {
            configurable_id: configurable_object.id,
            # Organizations will emit configurable_type of User, so we have to force this
            configurable_type: configurable_type,
          }.reverse_merge(configuration_defaults),
        )
      end
    end

    sig { abstract.returns(T::Hash[Symbol, T.any(Integer, Symbol)]) }
    def configuration_defaults; end
  end
end
