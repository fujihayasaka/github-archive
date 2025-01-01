# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Instrumentation
    class FeatureToggledPublisher
      extend T::Helpers

      abstract!

      sig do
        params(
          repository_id: Integer,
          owner_id: T.nilable(Integer),
          source_event: String,
          payload: T::Hash[T.untyped, T.untyped]
        ).void
      end
      def self.instrument_features_toggled(repository_id:, owner_id: nil, source_event: "", payload: {})
        repository = ::Repositories::Public.get_active_or_deleted(repository_id)
        unless repository.present?
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

        if repository.security_feature_configured?(:SECRET_SCANNING)
          GlobalInstrumenter.instrument("repository_secret_scanning.enable", { repository_id: repository.id })
        else
          GlobalInstrumenter.instrument("repository_secret_scanning.disable", { repository_id: repository.id })
        end

        if repository.security_feature_configured?(:SECRET_SCANNING_PUSH_PROTECTION)
          GlobalInstrumenter.instrument("repository_secret_scanning_push_protection.enable", { repository_id: repository.id })
        else
          GlobalInstrumenter.instrument("repository_secret_scanning_push_protection.disable", { repository_id: repository.id })
        end
      end
    end
  end
end
