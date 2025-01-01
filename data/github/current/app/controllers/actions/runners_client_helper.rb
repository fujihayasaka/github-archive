# typed: strict
# frozen_string_literal: true

require "github-launch"
require "github/launch_client"

# These are client wrappers to the Launch::Twirp::SelfHostedRunnersClient methods
module Actions::RunnersClientHelper
  include Api::App::ActionsRunnerAdminHelper
  include Api::App::ActionsScientistHelper

  class ListRunnersError < Actions::ServiceError; end

  private

  Entity = T.type_alias { T.any(Business, User, Repository) }

  sig { params(owner: Entity, name: String, use_runner_admin: T::Boolean, runner_group_id: Integer, labels: T::Array[String], work_folder: String, github_url: String, actor: User).returns(TwirpResponse) }
  def generate_jit_runner_config(owner, name:, use_runner_admin:, runner_group_id:, labels:, work_folder:, github_url:, actor:)
    if use_runner_admin
      resp = GitHub.build_runner_admin_client(owner).generate_jit_runner_config(
        owner: owner,
        name:,
        runner_group_id:,
        labels:,
        work_folder:,
        github_url:,
        actor: actor
      )

      return resp if resp.status != 403
    end

    Launch::Twirp.self_hosted_runners_client.generate_runner_config(
      owner,
      name:,
      runner_group_id:,
      labels:,
      work_folder:,
      github_url:,
      actor: actor
    )
  end

  sig { params(owner: Entity, runner_id: Integer, use_runner_admin: T::Boolean, do_experiment: T::Boolean, runner_admin_can_read_override: T::Boolean).returns(TwirpResponse) }
  def get_runner(owner, runner_id, use_runner_admin:, do_experiment: false, runner_admin_can_read_override: false)
    if use_runner_admin
      resp = GitHub.build_runner_admin_client(owner).get_runner(
        owner: owner,
        runner_id: runner_id,
        can_read_override: runner_admin_can_read_override || owner.feature_flag_enabled?(:actions_runners_use_runner_admin_service, default: false)
      )
    else
      resp = Launch::Twirp.self_hosted_runners_client.get_runner(
        owner,
        runner_id
      )
    end

    if do_experiment
      resp = do_experiment_with_fallbacks(
        experiment_name: "long_running.actions.runner.get_runner",
        original_response: resp,
        use_runner_admin: use_runner_admin,
        owner: owner,
        launch_func: -> { get_runner(owner, runner_id, use_runner_admin: false) },
        runner_admin_override_func: -> { get_runner(owner, runner_id, use_runner_admin: true, runner_admin_can_read_override: true) },
        compare_func: ->(control, candidate) { control&.status == candidate&.status && clean_runner(control&.value&.runner) == clean_runner(candidate&.value&.runner) },
        clean_func: ->(resp) { clean_runner(resp&.value&.runner) }
      )
    elsif use_runner_admin && resp.status == 403 && !runner_admin_can_read_override
      # Call to runner admin is not authorized, so fall back to Launch
      resp = get_runner(owner, runner_id, use_runner_admin: false)
    end

    resp
  end

  sig { params(owner: Entity, runner_id: Integer, use_runner_admin: T::Boolean, actor: User).returns([TwirpResponse, String]) }
  def delete_runner_helper(owner, runner_id, use_runner_admin:, actor:)
    if use_runner_admin
      resp = [GitHub.build_runner_admin_client(owner).delete_runner(
        owner: owner,
        runner_id: runner_id,
        actor: actor
      ), Actions::RunnerGroupsClientHelper::WRITTEN_TO_RUNNER_ADMIN]

      return resp if resp[0].status != 403
    end

    [Launch::Twirp.self_hosted_runners_client.delete_runner(
      owner,
      runner_id,
      actor: actor
    ), Actions::RunnerGroupsClientHelper::WRITTEN_TO_LAUNCH]
  end

  sig { params(owner: Entity, use_runner_admin: T::Boolean, do_experiment: T::Boolean, runner_admin_can_read_override: T::Boolean).returns(TwirpResponse) }
  def list_runner_downloads(owner, use_runner_admin:, do_experiment: false, runner_admin_can_read_override: false)
    if use_runner_admin
      resp = GitHub.build_runner_admin_client(owner).list_runner_downloads(
        owner: owner,
        can_read_override: runner_admin_can_read_override || owner.feature_flag_enabled?(:actions_runners_use_runner_admin_service, default: false)
      )
    else
      resp = Launch::Twirp.self_hosted_runners_client.list_downloads(owner)
    end

    if do_experiment
      resp = do_experiment_with_fallbacks(
        experiment_name: "long_running.actions.runner.list_runner_downloads",
        original_response: resp,
        use_runner_admin: use_runner_admin,
        owner: owner,
        launch_func: -> { list_runner_downloads(owner, use_runner_admin: false) },
        runner_admin_override_func: -> { list_runner_downloads(owner, use_runner_admin: true, runner_admin_can_read_override: true) },
        compare_func: ->(control, candidate) { control&.status == candidate&.status && clean_downloads(control&.value&.downloads) == clean_downloads(candidate&.value&.downloads) },
        clean_func: ->(resp) { clean_downloads(resp&.value&.downloads) }
      )
    elsif use_runner_admin && resp.status == 403 && !runner_admin_can_read_override
      # Call to runner admin is not authorized, so fall back to Launch
      resp = list_runner_downloads(owner, use_runner_admin: false)
    end

    resp
  end

  sig { params(owner: Entity, use_runner_admin: T::Boolean, page: Integer, per_page: Integer, pool_id: Integer, include_assigned_request: T::Boolean, name: String, do_experiment: T::Boolean, propagate_errors: T::Boolean, runner_admin_can_read_override: T::Boolean).returns(TwirpResponse) }
  def list_runners_helper(owner, use_runner_admin:, page: 0, per_page: 0, pool_id: 0, include_assigned_request: false, name: "", do_experiment: false, propagate_errors: false, runner_admin_can_read_override: false)
    # Set default pagination if name is provided
    if !name.blank?
      page = 0
      per_page = 0
    end

    if use_runner_admin
      resp = GitHub.build_runner_admin_client(owner).list_runners(
        owner: owner,
        name: name,
        page: page,
        per_page: per_page,
        include_assigned_request: include_assigned_request,
        can_read_override: runner_admin_can_read_override || owner.feature_flag_enabled?(:actions_runners_use_runner_admin_service, default: false)
      )
    else
      resp = Launch::Twirp.self_hosted_runners_client.list_runners(
        owner,
        page: page,
        per_page: per_page,
        pool_id: pool_id,
        include_assigned_request: include_assigned_request,
        name: name,
        exclude_elastic_runners: true
      )
    end

    if do_experiment
      resp = do_experiment_with_fallbacks(
        experiment_name: "long_running.actions.runner.list_runners",
        original_response: resp,
        use_runner_admin: use_runner_admin,
        owner: owner,
        launch_func: -> { list_runners_helper(owner, use_runner_admin: false, page: page, per_page: per_page, pool_id: pool_id, include_assigned_request: include_assigned_request, name: name, propagate_errors:) },
        runner_admin_override_func: -> { list_runners_helper(owner, use_runner_admin: true, page: page, per_page: per_page, pool_id: pool_id, include_assigned_request: include_assigned_request, name: name, propagate_errors:, runner_admin_can_read_override: true) },
        compare_func: ->(control, candidate) { control&.status == candidate&.status && clean_runners(control&.value&.runners) == clean_runners(candidate&.value&.runners) },
        clean_func: ->(resp) { clean_runners(resp&.value&.runners) }
      )
    elsif use_runner_admin && resp.status == 403 && !runner_admin_can_read_override
      # Call to runner admin is not authorized, so fall back to Launch
      resp = list_runners_helper(owner, use_runner_admin: false, page: page, per_page: per_page, pool_id: pool_id, include_assigned_request: include_assigned_request, name: name, propagate_errors:)
    end

    if propagate_errors && !resp.call_succeeded?
      Kernel.raise ListRunnersError.new("list_runners failed", status: resp.status, options: resp.options)
    end

    resp
  end

  sig { params(owner: Entity, use_runner_admin: T::Boolean, do_experiment: T::Boolean, runner_admin_can_read_override: T::Boolean).returns(TwirpResponse) }
  def list_labels(owner, use_runner_admin:, do_experiment: false, runner_admin_can_read_override: false)
    if use_runner_admin
      resp = GitHub.build_runner_admin_client(owner).list_labels(
        owner: owner,
        can_read_override: runner_admin_can_read_override || owner.feature_flag_enabled?(:actions_runners_use_runner_admin_service, default: false)
      )
    else
      resp = Launch::Twirp.self_hosted_runners_client.list_labels(owner)
    end

    if do_experiment
      resp = do_experiment_with_fallbacks(
        experiment_name: "long_running.actions.runner.list_labels",
        original_response: resp,
        use_runner_admin: use_runner_admin,
        owner: owner,
        launch_func: -> { list_labels(owner, use_runner_admin: false) },
        runner_admin_override_func: -> { list_labels(owner, use_runner_admin: true, runner_admin_can_read_override: true) },
        compare_func: ->(control, candidate) { control&.status == candidate&.status && clean_labels(control&.value&.labels) == clean_labels(candidate&.value&.labels) },
        clean_func: ->(resp) { clean_labels(resp&.value&.labels) }
      )
    elsif use_runner_admin && resp.status == 403 && !runner_admin_can_read_override
      # Call to runner admin is not authorized, so fall back to Launch
      resp = list_labels(owner, use_runner_admin: false)
    end

    resp
  end
end
