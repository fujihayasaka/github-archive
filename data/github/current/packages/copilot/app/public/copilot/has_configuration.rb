# typed: strict
# frozen_string_literal: true

module Copilot
  Configurable = T.type_alias { T.any(::Business, ::Organization, ::User) } # rubocop:todo Rails/ModuleNaming

  module HasConfiguration
    extend T::Helpers
    extend T::Sig

    abstract!

    include BaseHelpers::Helpers

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

    private

    sig { returns(Copilot::Configuration) }
    def configuration
      @configuration ||= T.let(
        retry_on_find_or_create_error(max_retry_count: 3) do
          load_configuration || create_configuration
        end,
        T.nilable(Copilot::Configuration),
      )
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
