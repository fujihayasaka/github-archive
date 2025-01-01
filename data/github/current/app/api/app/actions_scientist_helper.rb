# typed: true
# frozen_string_literal: true

require "github-launch"
require "github/launch_client"

module Api::App::ActionsScientistHelper
  sig { params(runner: T.nilable(T.any(GitHub::ActionsRunnerAdmin::Api::V1::Runner, GitHub::Launch::Services::Selfhostedrunners::Runner))).returns(Hash) }
  def clean_runner(runner)
    return {} unless runner
    labels_hash = runner.labels.map { |label| clean_label(label) }
    runner_hash = runner.to_h.except(:client_id, :created, :modified, :owner_id, :runner_status, :updates_disabled, :version).sort.to_h
    result_hash = runner_hash.merge(labels: labels_hash).compact
    result_hash
  end

  sig { params(runners: T.nilable(T.any(T::Array[GitHub::ActionsRunnerAdmin::Api::V1::Runner], T::Array[GitHub::Launch::Services::Selfhostedrunners::Runner]))).returns(T.nilable(T::Array[Hash])) }
  def clean_runners(runners)
    return nil unless runners
    runners.map { |runner| clean_runner(runner) }
  end

  sig { params(label: T.nilable(T.any(GitHub::ActionsRunnerAdmin::Api::V1::Label, GitHub::Launch::Services::Selfhostedrunners::Label))).returns(Hash) }
  def clean_label(label)
    return {} unless label
    label_hash = label.to_h.except(:id).sort.to_h
    label_hash
  end

  sig { params(download: T.nilable(T.any(GitHub::ActionsRunnerAdmin::Api::V1::Download, GitHub::Launch::Services::Selfhostedrunners::Download))).returns(Hash) }
  def clean_download(download)
    return {} unless download
    download_hash = download.to_h.except(:download_token, :sha256_hash).sort.to_h
    download_hash
  end

  sig { params(downloads: T.nilable(T.any(T::Array[GitHub::ActionsRunnerAdmin::Api::V1::Download], T::Array[GitHub::Launch::Services::Selfhostedrunners::Download]))).returns(T.nilable(T::Array[Hash])) }
  def clean_downloads(downloads)
    return nil unless downloads
    downloads.map { |download| clean_download(download) }
  end

  sig { params(runner_group: T.nilable(T.any(GitHub::ActionsRunnerAdmin::Api::V1::RunnerGroup, GitHub::Launch::Services::Runnergroups::RunnerGroup))).returns(Hash) }
  def clean_runner_group(runner_group)
    return {} unless runner_group
    owner_id_hash = runner_group.owner_id.to_h.except(:name).sort.to_h unless runner_group.owner_id.nil?
    runners_hash = runner_group.runners.map { |runner| clean_runner(runner) }
    visibility_normalized = runner_group.visibility.to_s.delete_prefix("VISIBILITY_").to_sym
    runner_group_hash = runner_group.to_h.except(:runners).sort.to_h
    result_hash = runner_group_hash.merge(runners: runners_hash).merge(owner_id: owner_id_hash).merge(visibility: visibility_normalized).compact
    result_hash
  end

  sig { params(runner_groups: T.nilable(T.any(T::Array[GitHub::ActionsRunnerAdmin::Api::V1::RunnerGroup], T::Array[GitHub::Launch::Services::Runnergroups::RunnerGroup]))).returns(T.nilable(T::Array[Hash])) }
  def clean_runner_groups(runner_groups)
    return nil unless runner_groups
    runner_groups.map { |runner_group| clean_runner_group(runner_group) }
  end

  sig { params(owner: T.any(Organization, Business, Repository, User)).returns(T::Boolean) }
  public def do_runner_admin_experiment?(owner)
    owner.feature_enabled?(:actions_runner_admin_enable_science_experiment)
  end
end
