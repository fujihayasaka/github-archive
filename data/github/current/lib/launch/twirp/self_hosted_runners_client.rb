# typed: strict
# frozen_string_literal: true

module Launch
  module Twirp
    class SelfHostedRunnersClient < Launch::Twirp::BaseClient

      Entity = T.type_alias { BaseClient::Entity }

      sig { params(owner: Entity, name: String).returns(TwirpResponse) }
      def create_label(owner, name)
        req = GitHub::Launch::Services::Selfhostedrunners::CreateLabelRequest.new(
          owner_id: identity(owner),
          name:,
        )

        rescue_rpc { client.create_label req }
      end

      sig do
        params(
          owner: Entity,
          runner_ids: T::Array[Integer],
          additions: T::Array[Integer],
          removals: T::Array[Integer],
        ).returns(TwirpResponse)
      end
      def bulk_update_labels(owner, runner_ids:, additions:, removals:)
        updates = runner_ids.map do |runner_id|
          GitHub::Launch::Services::Selfhostedrunners::BulkUpdateRunnerLabelsRequest::LabelOps.new(
            runner_id:,
            additions:,
            removals:,
          )
        end
        req = GitHub::Launch::Services::Selfhostedrunners::BulkUpdateRunnerLabelsRequest.new(
          owner_id: identity(owner),
          updates:,
        )

        rescue_rpc { client.bulk_update_runner_labels req }
      end

      sig { params(owner: Entity, runner_id: Integer).returns(TwirpResponse) }
      def get_runner(owner, runner_id)
        rpc(
          :GetRunner,
          owner_id: identity(owner),
          runner_id: runner_id
        )
      end

      sig do
        params(
          owner: Entity,
          name: String,
          runner_group_id: Integer,
          labels: T::Array[String],
          work_folder: String,
          github_url: String,
          actor: User,
        ).returns(TwirpResponse)
      end
      def generate_runner_config(owner, name:, runner_group_id:, labels:, work_folder:, github_url:, actor:)
        response = rpc(
          :GenerateJitRunnerConfig,
          owner_id: identity(owner),
          name:,
          runner_group_id:,
          labels:,
          work_folder:,
          github_url:
        )

        if response.call_succeeded?
          instrument_event(owner:, actor:, event: "configure_self_hosted_jit_runner")
        end

        response
      end

      sig { params(owner: Entity).returns(TwirpResponse) }
      def list_downloads(owner)
        rpc(
          :ListDownloads,
          repository_id: identity(owner)
        )
      end

      sig { params(owner: Entity).returns(TwirpResponse) }
      def list_labels(owner)
        rpc(
          :ListLabels,
          owner_id: identity(owner)
        )
      end

      sig do
        params(
          owner: Entity,
          page: Integer,
          per_page: Integer,
          pool_id: Integer,
          include_assigned_request: T::Boolean,
          name: String,
          exclude_elastic_runners: T::Boolean
        ).returns(TwirpResponse)
      end
      def list_runners(owner, page: 0, per_page: 0, pool_id: 0, include_assigned_request: false, name: "", exclude_elastic_runners: false)
        rpc(
          :ListRunnersV2,
          repository_id: identity(owner),
          page: page,
          per_page: per_page,
          pool_id: pool_id,
          include_assigned_request: include_assigned_request,
          name: name,
          exclude_elastic_runners: exclude_elastic_runners
        )
      end

      sig { params(owner: Entity, runner_id: Integer, label_ids: T::Array[Integer]).returns(TwirpResponse) }
      def replace_runner_labels(owner, runner_id:, label_ids:)
        updates = [
          GitHub::Launch::Services::Selfhostedrunners::BulkReplaceRunnerLabelsRequest::RunnerLabelsUpdate.new(
            runner_id:,
            label_ids:,
          )
        ]

        req = GitHub::Launch::Services::Selfhostedrunners::BulkReplaceRunnerLabelsRequest.new(
          owner_id: identity(owner),
          updates:,
        )

        rescue_rpc { client.bulk_replace_runner_labels req }
      end

      sig { params(owner: Entity, actor: User, instrument: T::Boolean).returns(TwirpResponse) }
      def get_runner_registration_token(owner, actor:, instrument: false)
        billing_owner = T.must(get_billing_owner(owner))

        # The first two parameters are identical, there is an issue for cleanup: https://github.com/github/c2c-actions-runtime/issues/1783
        response = rpc(
          :RegisterRunner,
          repository_id: identity(owner),
          owner_id: identity(owner),
          billing_owner_id: identity(billing_owner)
        )

        if response.call_succeeded?
          instrument_event(owner:, actor:, event: "register_self_hosted_runner") if instrument
        end

        response
      end

      sig { params(owner: Entity, actor: User, instrument: T::Boolean).returns(TwirpResponse) }
      def get_runner_removal_token(owner, actor:, instrument: false)
        # The parameters are identical, there is an issue for cleanup: https://github.com/github/c2c-actions-runtime/issues/1783
        response = rpc(
          :RegisterRunner,
          repository_id: identity(owner),
          owner_id: identity(owner)
        )

        if response.call_succeeded?
          instrument_event(owner:, actor:, event: "remove_self_hosted_runner") if instrument
        end

        response
      end

      sig { params(owner: Entity, runner_id: Integer, actor: User).returns(TwirpResponse) }
      def delete_runner(owner, runner_id, actor:)
        response = rpc(
          :DeleteRunner,
          repository_id: identity(owner),
          runner_id:
        )

        if response.call_succeeded?
          instrument_event(owner:, actor:, event: "remove_self_hosted_runner")
        end

        response
      end

      sig { params(runner_owner: Entity).returns(T.nilable(Entity)) }
      def get_billing_owner(runner_owner)
        return runner_owner if runner_owner.is_a?(Business) # runner_owner is an enterprise
        return runner_owner.business if runner_owner.business.present? # runner_owner is a repo or org within an enterprise
        return runner_owner if runner_owner.is_a?(Organization) # runner_owner is an org
        return T.must(runner_owner.owner) if runner_owner.is_a?(Repository) # runner_owner is a user or org
        nil #runner_owner is an unsupported entity
      end

      private

      sig { params(owner: Entity, event: String, actor: User).returns(T.untyped) }
      def instrument_event(owner:, event:, actor:)
        payload = {
          actor: actor,
        }

        case owner
        when Repository
          repo = owner
          payload[:repo] = repo
          payload[:org] = repo.owner if repo.owner.is_a? Organization
          GitHub.instrument "#{owner.event_prefix}.#{event}", payload
        when Organization
          payload[:org] = owner
          GitHub.instrument "#{owner.event_prefix}.#{event}", payload
        when Business
          payload[:business] = owner
          GitHub.instrument "enterprise.#{event}", payload
        end
      end

      sig { returns(T.class_of(GitHub::Launch::Services::Selfhostedrunners::SelfHostedRunnersClient)) }
      def twirp_class
        GitHub::Launch::Services::Selfhostedrunners::SelfHostedRunnersClient
      end
    end
  end
end
