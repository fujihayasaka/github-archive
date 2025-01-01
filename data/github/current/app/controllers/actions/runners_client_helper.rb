# typed: true
# frozen_string_literal: true

require "github-launch"
require "github/launch_client"

module Actions::RunnersClientHelper
  include Api::App::ActionsScientistHelper
  include Scientist

  private

  # The below methods were added to be shared with the API controllers
  # These are wrappers to the Launch::Twirp::SelfHostedRunnersClient methods
  Entity = T.type_alias { T.any(Business, User, Repository) }

  sig { params(owner: Entity, name: String, runner_group_id: Integer, labels: T::Array[String], work_folder: String, github_url: String, actor: User).returns(TwirpResponse) }
  def generate_jit_runner_config(owner, name:, runner_group_id:, labels:, work_folder:, github_url:, actor:)
    if use_runner_admin?(owner)
      GitHub.build_runner_admin_client(owner).generate_jit_runner_config(
        owner: owner,
        name:,
        runner_group_id:,
        labels:,
        work_folder:,
        github_url:,
        actor: actor
      )
    else
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
  end

  sig { params(owner: Entity, runner_id: Integer, use_runner_admin: T::Boolean, do_experiment: T::Boolean).returns(TwirpResponse) }
  def get_runner(owner, runner_id, use_runner_admin:, do_experiment: false)
    if do_experiment
      science "long_running.actions.runner.get_runner" do |e|
        e.use { get_runner(owner, runner_id, use_runner_admin: use_runner_admin, do_experiment: false) }
        e.try { get_runner(owner, runner_id, use_runner_admin: !use_runner_admin, do_experiment: false) }
        e.compare { |control, candidate| control&.status == candidate&.status && clean_runner(control&.value&.runner) == clean_runner(candidate&.value&.runner) }
        e.clean { |resp| clean_runner(resp&.value&.runner) }
      end
    end

    if use_runner_admin
      GitHub.build_runner_admin_client(owner).get_runner(
        owner: owner,
        runner_id: runner_id
      )
    else
      Launch::Twirp.self_hosted_runners_client.get_runner(
        owner,
        runner_id
      )
    end
  end

  sig { params(owner: Entity, runner_id: Integer, actor: User).returns(TwirpResponse) }
  def delete_runner_helper(owner, runner_id, actor:)
    if use_runner_admin?(owner)
      GitHub.build_runner_admin_client(owner).delete_runner(
        owner: owner,
        runner_id: runner_id,
        actor: actor
      )
    else
      Launch::Twirp.self_hosted_runners_client.delete_runner(
        owner,
        runner_id,
        actor: actor
      )
    end
  end

  sig { params(owner: Entity, use_runner_admin: T::Boolean, do_experiment: T::Boolean).returns(TwirpResponse) }
  def list_runner_downloads(owner, use_runner_admin:, do_experiment: false)
    if do_experiment
      science "long_running.actions.runner.list_runner_downloads" do |e|
        e.use { list_runner_downloads(owner, use_runner_admin: use_runner_admin, do_experiment: false) }
        e.try { list_runner_downloads(owner, use_runner_admin: !use_runner_admin, do_experiment: false) }
        e.compare { |control, candidate| control&.status == candidate&.status && clean_downloads(control&.value&.downloads) == clean_downloads(candidate&.value&.downloads) }
        e.clean { |resp| clean_downloads(resp&.value&.downloads) }
      end
    end

    if use_runner_admin
      GitHub.build_runner_admin_client(owner).list_runner_downloads(owner: owner)
    else
      Launch::Twirp.self_hosted_runners_client.list_downloads(owner)
    end
  end

  sig { params(owner: Entity, use_runner_admin: T::Boolean, page: Integer, per_page: Integer, pool_id: Integer, include_assigned_request: T::Boolean, name: String, exclude_elastic_runners: T::Boolean, do_experiment: T::Boolean).returns(TwirpResponse) }
  def list_runners_helper(owner, use_runner_admin:, page: 0, per_page: 0, pool_id: 0, include_assigned_request: false, name: "", exclude_elastic_runners: false, do_experiment: false)
    if do_experiment
      science "long_running.actions.runner.list_runners" do |e|
        e.use { list_runners_helper(owner, page: page, per_page: per_page, pool_id: pool_id, include_assigned_request: include_assigned_request, name: name, exclude_elastic_runners: exclude_elastic_runners, use_runner_admin: use_runner_admin, do_experiment: false) }
        e.try { list_runners_helper(owner, page: page, per_page: per_page, pool_id: pool_id, include_assigned_request: include_assigned_request, name: name, exclude_elastic_runners: exclude_elastic_runners, use_runner_admin: !use_runner_admin, do_experiment: false) }
        e.compare { |control, candidate| control&.status == candidate&.status && clean_runners(control&.value&.runners) == clean_runners(candidate&.value&.runners) }
        e.clean { |resp| clean_runners(resp&.value&.runners) }
      end
    end

    # Set default pagination if name is provided
    if !name.blank?
      page = 0
      per_page = 0
    end

    if use_runner_admin
      GitHub.build_runner_admin_client(owner).list_runners(
        owner: owner,
        name: name,
        page: page,
        per_page: per_page
      )
    else
      Launch::Twirp.self_hosted_runners_client.list_runners(
        owner,
        page: page,
        per_page: per_page,
        pool_id: pool_id,
        include_assigned_request: include_assigned_request,
        name: name,
        exclude_elastic_runners: exclude_elastic_runners
      )
    end
  end

  sig { params(owner: T.any(Organization, Business, Repository, User)).returns(T::Boolean) }
  public def use_runner_admin?(owner)
    owner.feature_enabled?(:actions_runners_use_runner_admin_service)
  end
end
