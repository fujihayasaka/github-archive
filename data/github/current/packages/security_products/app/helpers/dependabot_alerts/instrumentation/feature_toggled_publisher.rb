# typed: strict
# frozen_string_literal: true

module DependabotAlerts
  module Instrumentation
    class FeatureToggledPublisher
      extend T::Helpers

      abstract!

      # TODO: need to address replication latency
      # https://github.com/github/security-center/issues/3299
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

        if repository.security_feature_configured?(:DEPENDABOT_ALERTS)
          GlobalInstrumenter.instrument("repository_vulnerability_alerts.enable", { repo: repository })
        else
          GlobalInstrumenter.instrument("repository_vulnerability_alerts.disable", { repo: repository })
        end
      end
    end
  end
end
