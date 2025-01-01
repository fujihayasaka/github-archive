# typed: strict
# frozen_string_literal: true

module Launch
  module Twirp
    class RunnerScaleSetsClient < Launch::Twirp::BaseClient

      Entity = T.type_alias { BaseClient::Entity }

      sig { void }
      def initialize
        super(request_timeout_secs: 3.0)
      end

      sig { params(owner: Entity, scale_set_id: Integer).returns(TwirpResponse) }
      def get_scale_set(owner, scale_set_id)
        rpc(
          :GetRunnerScaleSet,
          owner_id: identity(owner),
          scale_set_id: scale_set_id
        )
      end

      sig { params(owner: Entity, exclude_elastic_runners: T::Boolean).returns(TwirpResponse) }
      def list_scale_sets(owner, exclude_elastic_runners: false)
        rpc(
          :ListRunnerScaleSets,
          owner_id: identity(owner),
          exclude_elastic_runners: exclude_elastic_runners
        )
      end

      private

      sig { returns(T.class_of(GitHub::Launch::Services::Runnerscalesets::RunnerScaleSetsClient)) }
      def twirp_class
        GitHub::Launch::Services::Runnerscalesets::RunnerScaleSetsClient
      end
    end
  end
end
