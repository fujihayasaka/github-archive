# typed: strict
# frozen_string_literal: true

module CodeScanning
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

        code_scanning_enabled = code_scanning_enabled?(source_event, repository, payload)
        # Don't instrument if we don't get a return value from code scanning or if there was an error.
        if code_scanning_enabled.nil?
          GitHub.logger.info(
            "No enablement status returned from Turboscan",
            "code.namespace": self.name,
            "code.function": __method__
          )
          return
        end

        if code_scanning_enabled
          GlobalInstrumenter.instrument("code_scanning.enable", { repository_id: repository_id })
        else
          GlobalInstrumenter.instrument("code_scanning.disable", { repository_id: repository_id })
        end
      end

      sig { params(source_event: String, repository: Repository, payload: T::Hash[Symbol, T.untyped]).returns(T.nilable(T::Boolean)) }
      def self.code_scanning_enabled?(source_event, repository, payload)
        if source_event == "hydro.schemas.code_scanning.v0.EnablementEvent"
          # Direct toggle event from turboscan, fetch enablement status from payload.
          payload.dig(:enabled)
        else
          # Fanout event. Fetch status based on analysis from turboscan.
          repository.security_feature_configured?(:CODE_SCANNING)
        end
      end
    end
  end
end
