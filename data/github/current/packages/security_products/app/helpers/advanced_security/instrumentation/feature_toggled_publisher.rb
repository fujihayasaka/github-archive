# typed: strict
# frozen_string_literal: true

module AdvancedSecurity
  module Instrumentation
    class FeatureToggledPublisher
      extend T::Helpers
      extend T::Sig

      abstract!

      sig do
        params(
          repository_id: Integer,
          owner_id: T.nilable(Integer),
          source_event: String,
          payload: T::Hash[Symbol, T.untyped]
        ).void
      end
      def self.instrument_features_toggled(repository_id:, owner_id: nil, source_event: "", payload: {})
        repository = ::Repositories::Public.get_active_or_deleted(repository_id)
        if repository.blank?
          GitHub.logger.info(
            "Repository not found.",
            "code.namespace": self.name,
            "code.function": __method__
          )
          return
        end

        owner = if owner_id.nil?
          repository.owner
        else
          ::User.find_by(id: owner_id)
        end

        if owner.nil?
          GitHub.logger.info(
            "Owner not found.",
            "code.namespace": self.name,
            "code.function": __method__
          )
          return
        end

        if repository.security_feature_configured?(:ADVANCED_SECURITY)
          GlobalInstrumenter.instrument("advanced_security.enabled", { repository_id: repository_id })
        else
          GlobalInstrumenter.instrument("advanced_security.disabled", { repository_id: repository_id })
        end
      end
    end
  end
end
