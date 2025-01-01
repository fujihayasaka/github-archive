# typed: strict
# frozen_string_literal: true

module Launch
  module Twirp
    class RunnerScaleSetsClient < Launch::Twirp::BaseClient

      Entity = T.type_alias { BaseClient::Entity }

      sig { params(retry_options: T.nilable(T::Hash[Symbol, T.untyped])).void }
      def initialize(retry_options: nil)
        super(request_timeout_secs: 3.0, retry_options:)
      end

      sig { params(owner: Entity, scale_set_id: Integer).returns(TwirpResponse) }
      def get_scale_set(owner, scale_set_id)
        rpc(
          :GetRunnerScaleSet,
          owner_id: identity(owner),
          scale_set_id: scale_set_id
        )
      end

      sig { params(owner: Entity, name: T.nilable(String), group_id: T.nilable(Integer), exclude_elastic_runners: T::Boolean, page: T.nilable(Integer), per_page: T.nilable(Integer)).returns(TwirpResponse) }
      def list_scale_sets(owner, name: nil, group_id: nil, exclude_elastic_runners: false, page: nil, per_page: nil)
        rpc(
          :ListRunnerScaleSets,
          owner_id: identity(owner),
          exclude_elastic_runners: exclude_elastic_runners,
          runner_scale_set_name: name,
          runner_group_id: group_id
        )
      end

      sig { params(owner: Entity, name: String, group_id: Integer, labels: T::Array[T.untyped], runner_setting_hash: T::Hash[Symbol, T::Boolean]).returns(TwirpResponse) }
      def add_runner_scale_set(owner, name:, group_id:, labels:, runner_setting_hash:)
        rpc(
          :AddRunnerScaleSet,
          owner_id: identity(owner),
          name: name,
          runner_group_id: group_id,
          labels: labels,
          runner_setting: runner_setting(runner_setting_hash)
        )
      end

      sig { params(owner: Entity, scale_set_id: Integer, name: String, labels: T::Array[T.untyped], runner_setting_hash: T.untyped, group_id: T.nilable(Integer)).returns(TwirpResponse) }
      def update_runner_scale_set(owner, scale_set_id:, name:, labels:, runner_setting_hash:, group_id: nil)
        rpc(
          :UpdateRunnerScaleSet,
          owner_id: identity(owner),
          scale_set_id: scale_set_id,
          name: name,
          runner_group_id: group_id,
          labels: labels,
          runner_setting: runner_setting(runner_setting_hash)
        )
      end

      sig { params(owner: Entity, scale_set_id: Integer).returns(TwirpResponse) }
      def delete_runner_scale_set(owner, scale_set_id:)
        rpc(
          :DeleteRunnerScaleSet,
          owner_id: identity(owner),
          scale_set_id: scale_set_id
        )
      end

      sig { params(owner: Entity, scale_set_id: Integer, session_owner_name: String).returns(TwirpResponse) }
      def create_runner_scale_set_session(owner, scale_set_id:, session_owner_name:)
        rpc(
          :CreateRunnerScaleSetSession,
          owner_id: identity(owner),
          scale_set_id: scale_set_id,
          owner_name: session_owner_name
        )
      end

      sig { params(owner: Entity, scale_set_id: Integer, session_id: String).returns(TwirpResponse) }
      def refresh_runner_scale_set_session(owner, scale_set_id:, session_id:)
        rpc(
          :RefreshRunnerScaleSetSession,
          owner_id: identity(owner),
          scale_set_id: scale_set_id,
          session_id: session_id
        )
      end

      sig { params(owner: Entity, scale_set_id: Integer, session_id: String).returns(TwirpResponse) }
      def delete_runner_scale_set_session(owner, scale_set_id:, session_id:)
        rpc(
          :DeleteRunnerScaleSetSession,
          owner_id: identity(owner),
          scale_set_id: scale_set_id,
          session_id: session_id
        )
      end

      sig { params(owner: Entity, scale_set_id: Integer, name: T.nilable(String), work_folder: T.nilable(String)).returns(TwirpResponse) }
      def generate_jit_runner_config_for_scale_set(owner, scale_set_id:, name:, work_folder:)
        rpc(
          :GenerateRunnerScaleSetJitRunnerConfig,
          owner_id: identity(owner),
          scale_set_id: scale_set_id,
          name: name,
          work_folder: work_folder
        )
      end

      private

      sig { params(runner_setting_hash: T.nilable(T::Hash[Symbol, T.untyped])).returns(T.nilable(GitHub::Launch::Services::Runnerscalesets::RunnerSetting)) }
      def runner_setting(runner_setting_hash)
        return nil unless runner_setting_hash
        GitHub::Launch::Services::Runnerscalesets::RunnerSetting.new(
          disable_update: runner_setting_hash[:disableUpdate],
          ephemeral: runner_setting_hash[:ephemeral])
      end

      sig { returns(T.class_of(GitHub::Launch::Services::Runnerscalesets::RunnerScaleSetsClient)) }
      def twirp_class
        GitHub::Launch::Services::Runnerscalesets::RunnerScaleSetsClient
      end
    end
  end
end
