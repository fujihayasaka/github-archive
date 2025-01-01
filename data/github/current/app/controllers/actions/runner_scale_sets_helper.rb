# typed: strict
# frozen_string_literal: true

require "github-launch"
require "github/launch_client"

module Actions::RunnerScaleSetsHelper
  extend ActiveSupport::Concern
  include Api::App::ActionsRunnerAdminHelper
  include Api::App::ActionsScientistHelper

  Entity = T.type_alias { T.any(Business, Organization, Repository) }

  # List runner scale sets for an owner (organization, repository, or enterprise)
  sig { params(owner: Entity, use_runner_admin: T::Boolean, name: T.nilable(String), group_id: T.nilable(Integer), page: T.nilable(Integer), per_page: T.nilable(Integer), do_experiment: T::Boolean, runner_admin_can_read_override: T::Boolean).returns(TwirpResponse) }
  def list_runner_scale_sets(owner, use_runner_admin:, name: nil, group_id: nil, page: nil, per_page: nil, do_experiment: false, runner_admin_can_read_override: false)
    GitHub.tracer.in_span("actions/runner_scale_sets_helper.list", kind: :internal, attributes: {
      "entity_type" => "RunnerScaleSet",
      "owner_type" => owner.class.name,
    }) do
      if use_runner_admin
        resp = GitHub.build_runner_admin_client(owner).list_runner_scale_sets(
          owner: owner,
          name: name,
          group_id: group_id,
          page: page,
          per_page: per_page,
          can_read_override: runner_admin_can_read_override || owner.feature_flag_enabled?(:actions_runners_use_runner_admin_service, default: false),
        )
      else
        resp = Launch::Twirp::runner_scale_sets_client.list_scale_sets(
          owner,
          exclude_elastic_runners: true,
          name: name,
          group_id: group_id,
          page: page,
          per_page: per_page
        )
      end

      if do_experiment
        resp = do_experiment_with_fallbacks(
          experiment_name: "long_running.actions.runner_scale_set.list_runner_scale_sets",
          original_response: resp,
          use_runner_admin: use_runner_admin,
          owner: owner,
          launch_func: -> { list_runner_scale_sets(owner, use_runner_admin: false, name: name, group_id: group_id, page: page, per_page: per_page) },
          runner_admin_override_func: -> { list_runner_scale_sets(owner, use_runner_admin: true, name: name, group_id: group_id, page: page, per_page: per_page, runner_admin_can_read_override: true) },
          compare_func: ->(control, candidate) { control&.status == candidate&.status && clean_runner_scale_sets(control&.value&.runner_scale_sets) == clean_runner_scale_sets(candidate&.value&.runner_scale_sets) },
          clean_func: ->(resp) { clean_runner_scale_sets(resp&.value&.runner_scale_sets) }
        )
      elsif use_runner_admin && resp.status == 403 && !runner_admin_can_read_override
        # Call to runner admin is not authorized, so fall back to Launch
        resp = list_runner_scale_sets(owner, use_runner_admin: false, name: name, group_id: group_id, page: page, per_page: per_page)
      end

      resp
    end
  end

  # Get a specific runner scale set by ID
  sig { params(owner: Entity, id: Integer, use_runner_admin: T::Boolean, do_experiment: T::Boolean, runner_admin_can_read_override: T::Boolean).returns(TwirpResponse) }
  def get_runner_scale_set(owner, id:, use_runner_admin:, do_experiment: false, runner_admin_can_read_override: false)
    GitHub.tracer.in_span("actions/runner_scale_sets_helper.get", kind: :internal, attributes: {
      "entity_type" => "RunnerScaleSet",
      "owner_type" => owner.class.name,
    }) do
      if use_runner_admin
        resp = GitHub.build_runner_admin_client(owner).get_runner_scale_set(
          owner: owner,
          scale_set_id: id,
          can_read_override: runner_admin_can_read_override || owner.feature_flag_enabled?(:actions_runners_use_runner_admin_service, default: false),
        )
      else
        resp = Launch::Twirp::runner_scale_sets_client.get_scale_set(owner, id)
      end

      if do_experiment
        resp = do_experiment_with_fallbacks(
          experiment_name: "long_running.actions.runner_scale_set.get_runner_scale_set",
          original_response: resp,
          use_runner_admin: use_runner_admin,
          owner: owner,
          launch_func: -> { get_runner_scale_set(owner, id: id, use_runner_admin: false) },
          runner_admin_override_func: -> { get_runner_scale_set(owner, id: id, use_runner_admin: true, runner_admin_can_read_override: true) },
          compare_func: ->(control, candidate) { control&.status == candidate&.status && clean_runner_scale_set(control&.value&.runner_scale_set) == clean_runner_scale_set(candidate&.value&.runner_scale_set) },
          clean_func: ->(resp) { clean_runner_scale_set(resp&.value&.runner_scale_set) }
        )
      elsif use_runner_admin && resp.status == 403 && !runner_admin_can_read_override
        # Call to runner admin is not authorized, so fall back to Launch
        resp = get_runner_scale_set(owner, id: id, use_runner_admin: false)
      end

      resp
    end
  end

  # Create a new runner scale set
  sig { params(owner: Entity, use_runner_admin: T::Boolean, name: String, group_id: Integer, labels: T.untyped, runner_setting_hash: T.untyped).returns(TwirpResponse) }
  def add_runner_scale_set(owner, use_runner_admin:, name:, group_id:, labels:, runner_setting_hash:)
    GitHub.tracer.in_span("actions/runner_scale_sets_helper.create", kind: :internal, attributes: {
      "entity_type" => "RunnerScaleSet",
      "owner_type" => owner.class.name,
    }) do
      if use_runner_admin
        resp = GitHub.build_runner_admin_client(owner).add_runner_scale_set(
          owner: owner,
          name: name,
          group_id: group_id,
          labels: labels,
          runner_setting_hash: runner_setting_hash
        )

        return resp if resp.status != 403
      end

      Launch::Twirp::runner_scale_sets_client.add_runner_scale_set(
        owner,
        name: name,
        group_id: group_id,
        labels: labels,
        runner_setting_hash: runner_setting_hash
      )
    end
  end

  # Update an existing runner scale set
  sig { params(owner: Entity, use_runner_admin: T::Boolean, scale_set_id: Integer, name: String, labels: T.untyped, runner_setting_hash: T.untyped, group_id: T.nilable(Integer)).returns(TwirpResponse) }
  def update_runner_scale_set(owner, use_runner_admin:, scale_set_id:, name:, labels:, runner_setting_hash:, group_id: nil)
    GitHub.tracer.in_span("actions/runner_scale_sets_helper.update", kind: :internal, attributes: {
      "entity_type" => "RunnerScaleSet",
      "owner_type" => owner.class.name,
    }) do
      if use_runner_admin
        resp = GitHub.build_runner_admin_client(owner).update_runner_scale_set(
          owner: owner,
          scale_set_id: scale_set_id,
          name: name,
          group_id: group_id,
          labels: labels,
          runner_setting_hash: runner_setting_hash
        )

        return resp if resp.status != 403
      end

      Launch::Twirp::runner_scale_sets_client.update_runner_scale_set(
        owner,
        scale_set_id: scale_set_id,
        name: name,
        labels: labels,
        runner_setting_hash: runner_setting_hash,
        group_id: group_id
      )
    end
  end

  # Delete a runner scale set
  sig { params(owner: Entity, use_runner_admin: T::Boolean, scale_set_id: Integer).returns(TwirpResponse) }
  def delete_runner_scale_set(owner, use_runner_admin:, scale_set_id:)
    GitHub.tracer.in_span("actions/runner_scale_sets_helper.delete", kind: :internal, attributes: {
      "entity_type" => "RunnerScaleSet",
      "owner_type" => owner.class.name,
    }) do
      if use_runner_admin
        resp = GitHub.build_runner_admin_client(owner).delete_runner_scale_set(
          owner: owner,
          scale_set_id: scale_set_id
        )

        return resp if resp.status != 403
      end

      Launch::Twirp::runner_scale_sets_client.delete_runner_scale_set(
        owner,
        scale_set_id: scale_set_id
      )
    end
  end

  # Create a runner scale set session
  sig { params(owner: Entity, use_runner_admin: T::Boolean, scale_set_id: Integer, session_owner_name: String).returns(TwirpResponse) }
  def add_runner_scale_set_session(owner, use_runner_admin:, scale_set_id:, session_owner_name:)
    GitHub.tracer.in_span("actions/runner_scale_sets_helper.create_session", kind: :internal, attributes: {
      "entity_type" => "RunnerScaleSet",
      "owner_type" => owner.class.name,
    }) do
      if use_runner_admin
        resp = GitHub.build_runner_admin_client(owner).create_runner_scale_set_session(
          owner: owner,
          scale_set_id: scale_set_id,
          session_owner_name: session_owner_name
        )

        return resp if resp.status != 403
      end

      Launch::Twirp::runner_scale_sets_client.create_runner_scale_set_session(
        owner,
        scale_set_id: scale_set_id,
        session_owner_name: session_owner_name
      )
    end
  end

  # Refresh a runner scale set session
  sig { params(owner: Entity, use_runner_admin: T::Boolean, scale_set_id: Integer, session_id: String).returns(TwirpResponse) }
  def refresh_runner_scale_set_session(owner, use_runner_admin:, scale_set_id:, session_id:)
    GitHub.tracer.in_span("actions/runner_scale_sets_helper.refresh_session", kind: :internal, attributes: {
      "entity_type" => "RunnerScaleSet",
      "owner_type" => owner.class.name,
    }) do
      if use_runner_admin
        resp = GitHub.build_runner_admin_client(owner).refresh_runner_scale_set_session(
          owner: owner,
          scale_set_id: scale_set_id,
          session_id: session_id
        )

        return resp if resp.status != 403
      end

      Launch::Twirp::runner_scale_sets_client.refresh_runner_scale_set_session(
        owner,
        scale_set_id: scale_set_id,
        session_id: session_id
      )
    end
  end

  # Delete a runner scale set session
  sig { params(owner: Entity, use_runner_admin: T::Boolean, scale_set_id: Integer, session_id: String).returns(TwirpResponse) }
  def delete_runner_scale_set_session(owner, use_runner_admin:, scale_set_id:, session_id:)
    GitHub.tracer.in_span("actions/runner_scale_sets_helper.delete_session", kind: :internal, attributes: {
      "entity_type" => "RunnerScaleSet",
      "owner_type" => owner.class.name,
    }) do
      if use_runner_admin
        resp = GitHub.build_runner_admin_client(owner).delete_runner_scale_set_session(
          owner: owner,
          scale_set_id: scale_set_id
        )

        return resp if resp.status != 403
      end

      Launch::Twirp::runner_scale_sets_client.delete_runner_scale_set_session(
        owner,
        scale_set_id: scale_set_id,
        session_id: session_id
      )
    end
  end

  # Generate JIT config for a runner scale set
  sig { params(owner: Entity, use_runner_admin: T::Boolean, scale_set_id: Integer, name: T.nilable(String), work_folder: T.nilable(String)).returns(TwirpResponse) }
  def generate_jit_config(owner, use_runner_admin:, scale_set_id:, name:, work_folder:)
    GitHub.tracer.in_span("actions/runner_scale_sets_helper.generate_jit_config", kind: :internal, attributes: {
      "entity_type" => "RunnerScaleSet",
      "owner_type" => owner.class.name,
    }) do
      if use_runner_admin
        resp = GitHub.build_runner_admin_client(owner).generate_jit_runner_config_for_scale_set(
          owner: owner,
          scale_set_id: scale_set_id,
          name: name,
          work_folder: work_folder
        )

        return resp if resp.status != 403
      end

      Launch::Twirp::runner_scale_sets_client.generate_jit_runner_config_for_scale_set(
        owner,
        scale_set_id: scale_set_id,
        name: name,
        work_folder: work_folder
      )
    end
  end
end
