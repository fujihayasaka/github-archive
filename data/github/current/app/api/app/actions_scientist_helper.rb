# typed: strict
# frozen_string_literal: true

require "github-launch"
require "github/launch_client"

module Api::App::ActionsScientistHelper
  include Scientist

  sig { params(runner: T.nilable(T.any(GitHub::ActionsRunnerAdmin::Api::V1::Runner, GitHub::Launch::Services::Selfhostedrunners::Runner))).returns(T::Hash[T.untyped, T.untyped]) }
  def clean_runner(runner)
    return {} unless runner
    labels_hash = clean_labels(runner.labels.to_a)
    runner_hash = runner.to_h.except(:assigned_request, :client_id, :created, :current_parallelism, :labels, :modified, :owner_id, :runner_status, :status, :updates_disabled, :version)
    result_hash = runner_hash.merge(labels: labels_hash).sort.to_h
    result_hash
  end

  sig { params(runners: T.nilable(T.any(T::Array[GitHub::ActionsRunnerAdmin::Api::V1::Runner], T::Array[GitHub::Launch::Services::Selfhostedrunners::Runner]))).returns(T.nilable(T::Array[T::Hash[T.untyped, T.untyped]])) }
  def clean_runners(runners)
    return nil unless runners
    runners.sort_by(&:id).map { |runner| clean_runner(runner) }
  end

  sig { params(runner_scale_set: T.nilable(T.any(GitHub::ActionsRunnerAdmin::Api::V1::RunnerScaleSet, GitHub::Launch::Services::Runnerscalesets::RunnerScaleSet))).returns(T::Hash[T.untyped, T.untyped]) }
  def clean_runner_scale_set(runner_scale_set)
    return {} unless runner_scale_set
    labels_hash = clean_labels(runner_scale_set.labels.to_a)
    statistics_hash = clean_runner_scale_set_statistics(runner_scale_set.statistics)
    runner_setting_hash = clean_runner_scale_set_setting(runner_scale_set.runner_setting)
    runner_scale_set_hash = runner_scale_set.to_h.except(:acquire_jobs_url, :create_session_url, :created, :created_on, :enabled, :get_acquirable_jobs_url, :owner_id, :queue_name, :runner_jit_config_url, :runner_setting, :statistics)
    result_hash = runner_scale_set_hash.merge(labels: labels_hash, statistics: statistics_hash, runner_setting: runner_setting_hash).sort.to_h
    result_hash
  end

  sig { params(runner_scale_sets: T.nilable(T.any(T::Array[GitHub::ActionsRunnerAdmin::Api::V1::RunnerScaleSet], T::Array[GitHub::Launch::Services::Runnerscalesets::RunnerScaleSet]))).returns(T.nilable(T::Array[T::Hash[T.untyped, T.untyped]])) }
  def clean_runner_scale_sets(runner_scale_sets)
    return nil unless runner_scale_sets
    runner_scale_sets.sort_by(&:id).map { |runner_scale_set| clean_runner_scale_set(runner_scale_set) }
  end

  sig { params(statistics: T.nilable(T.any(GitHub::ActionsRunnerAdmin::Api::V1::RunnerScaleSetStatistics, GitHub::Launch::Services::Runnerscalesets::RunnerScaleSetStatistics))).returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
  def clean_runner_scale_set_statistics(statistics)
    return {} unless statistics
    statistics_hash = statistics.to_h.sort.to_h
    statistics_hash
  end

  sig { params(runner_setting: T.nilable(T.any(GitHub::ActionsRunnerAdmin::Api::V1::RunnerSetting, GitHub::Launch::Services::Runnerscalesets::RunnerSetting))).returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
  def clean_runner_scale_set_setting(runner_setting)
    return {} unless runner_setting
    runner_setting_hash = runner_setting.to_h.sort.to_h
    runner_setting_hash
  end

  sig { params(label: T.nilable(T.any(GitHub::ActionsRunnerAdmin::Api::V1::Label, GitHub::Launch::Services::Selfhostedrunners::Label, GitHub::ActionsRunnerAdmin::Api::V1::RunnerScaleSetLabel, GitHub::Launch::Services::Runnerscalesets::Label))).returns(T::Hash[T.untyped, T.untyped]) }
  def clean_label(label)
    return {} unless label
    label_hash = label.to_h.except(:id).sort.to_h
    label_hash
  end

  sig { params(labels: T.nilable(T.any(T::Array[GitHub::ActionsRunnerAdmin::Api::V1::Label], T::Array[GitHub::Launch::Services::Selfhostedrunners::Label], T::Array[GitHub::ActionsRunnerAdmin::Api::V1::RunnerScaleSetLabel], T::Array[GitHub::Launch::Services::Runnerscalesets::Label]))).returns(T.nilable(T::Array[T::Hash[T.untyped, T.untyped]])) }
  def clean_labels(labels)
    return nil unless labels
    labels.sort_by(&:name).map { |label| clean_label(label) }
  end

  sig { params(download: T.nilable(T.any(GitHub::ActionsRunnerAdmin::Api::V1::Download, GitHub::Launch::Services::Selfhostedrunners::Download))).returns(T::Hash[T.untyped, T.untyped]) }
  def clean_download(download)
    return {} unless download
    download_hash = download.to_h.except(:download_token, :sha256_hash).sort.to_h
    download_hash
  end

  sig { params(downloads: T.nilable(T.any(T::Array[GitHub::ActionsRunnerAdmin::Api::V1::Download], T::Array[GitHub::Launch::Services::Selfhostedrunners::Download]))).returns(T.nilable(T::Array[T::Hash[T.untyped, T.untyped]])) }
  def clean_downloads(downloads)
    return nil unless downloads
    downloads.sort_by(&:filename).map { |download| clean_download(download) }
  end

  sig { params(runner_group: T.nilable(T.any(GitHub::ActionsRunnerAdmin::Api::V1::RunnerGroup, GitHub::Launch::Services::Runnergroups::RunnerGroup))).returns(T::Hash[T.untyped, T.untyped]) }
  def clean_runner_group(runner_group)
    return {} unless runner_group
    owner_id_hash = clean_owner_id(runner_group.owner_id)
    runners_hash = runner_group.runners.sort_by(&:id).map { |runner| clean_runner(runner) }
    runner_scale_sets_hash = runner_group.runner_scale_sets.sort_by(&:id).map { |runner_scale_set| clean_runner_scale_set(runner_scale_set) }
    selected_targets_hash = runner_group.selected_targets.sort_by(&:global_id).map { |target| clean_owner_id(target) }
    runner_group.selected_workflow_refs.sort!
    visibility_normalized = runner_group.visibility.to_s.delete_prefix("VISIBILITY_").to_sym
    runner_group_hash = runner_group.to_h.except(:owner_id, :runner_scale_sets, :runners, :selected_targets, :size, :visibility)
    result_hash = runner_group_hash
      .merge(
        runners: runners_hash,
        runner_scale_sets: runner_scale_sets_hash,
        selected_targets: selected_targets_hash,
        owner_id: owner_id_hash,
        visibility: visibility_normalized
      )
      .sort
      .to_h
    result_hash
  end

  sig { params(owner_id: T.nilable(T.any(GitHub::ActionsRunnerAdmin::Entities::V1::Identity, GitHub::Launch::Pbtypes::GitHub::Identity))).returns(T::Hash[T.untyped, T.untyped]) }
  def clean_owner_id(owner_id)
    return {} unless owner_id
    owner_id_hash = owner_id.to_h.except(:name).sort.to_h
    owner_id_hash
  end

  sig { params(runner_groups: T.nilable(T.any(T::Array[GitHub::ActionsRunnerAdmin::Api::V1::RunnerGroup], T::Array[GitHub::Launch::Services::Runnergroups::RunnerGroup]))).returns(T.nilable(T::Array[T::Hash[T.untyped, T.untyped]])) }
  def clean_runner_groups(runner_groups)
    return nil unless runner_groups
    runner_groups.sort_by(&:id).map { |runner_group| clean_runner_group(runner_group) }
  end

  sig { params(owner: T.any(Organization, Business, Repository, User)).returns(T::Boolean) }
  public def do_runner_admin_experiment?(owner)
    owner.feature_flag_enabled_or_raise?(:actions_runner_admin_enable_science_experiment) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
  end

  sig { params(experiment_name: String, original_response: TwirpResponse, use_runner_admin: T::Boolean, owner: T.any(Organization, Business, Repository, User), launch_func: T.proc.returns(TwirpResponse), runner_admin_override_func: T.proc.returns(TwirpResponse), compare_func: T.proc.params(control: T.untyped, candidate: T.untyped).returns(T.untyped), clean_func: T.proc.params(resp: T.untyped).returns(T.untyped)).returns(TwirpResponse) }
  public def do_experiment_with_fallbacks(experiment_name:, original_response:, use_runner_admin:, owner:, launch_func:, runner_admin_override_func:, compare_func:, clean_func:)
    science experiment_name do |e|
      e.context use_runner_admin: use_runner_admin, owner_global_id: owner.next_global_id, owner_name: owner.name
      e.use do
        if use_runner_admin && original_response.status == 403
          # Call to runner admin is not authorized, so fall back to Launch
          next launch_func.call
        else
          # Call to runner admin succeeded, so return the original response
          next original_response
        end
      end
      e.try do
        # Control called launch, or call to runner admin is not authorized, try-block should still force auth to runner admin for experiment
        if !use_runner_admin || original_response.status == 403
          next runner_admin_override_func.call
        else
          # Call to runner admin succeeded, so call launch for experiment
          next launch_func.call
        end
      end
      e.compare { |control, candidate| compare_func.call(control, candidate) }
      e.clean { |resp| clean_func.call(resp) }
    end
  end
end
