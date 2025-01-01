# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Instrumentation
    # This class builds and publishes EnablementChange events for TSS to consume. This event contains information
    # about which secret scanning realted features a repo has enabled.
    class EnablementChangePublisher
      extend T::Sig

      sig { params(repo: Repository).void }
      def self.publish_enablement_change_event_for_repository(repo:)
        capabilities = SecretScanning::Features::Repo::Capabilities.new(repo)
        Hydro::PublishRetrier.publish(capabilities.to_hydro_msg, schema: "token_scanning_service.v0.EnablementChange")
      end
    end
  end
end
