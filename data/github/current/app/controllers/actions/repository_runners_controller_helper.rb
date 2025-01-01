# typed: strict
# frozen_string_literal: true

module Actions::RepositoryRunnersControllerHelper
  include GitHub::Memoizer
  include ::Actions::LargerRunnersHelper
  include Actions::RunnersClientHelper

  extend T::Helpers

  # This anti-pattern, tracking issue [here](https://github.com/github/octogrowth/issues/2561)
  requires_ancestor { Actions::RepositoryRunnersController }

  class Runner < T::Struct
    const :name, String
    const :labels, T::Array[String]
    const :description, String
    const :os, String
    const :source, String
  end

  sig { returns(T::Array[Runner]) }
  memoize def fetch_larger_runners
    owner = current_repository.owner
    return [] unless owner.organization?
    return [] unless owner.can_use_larger_runners?

    Actions::LargerRunner.larger_runners_for(entity: current_repository, owner: owner).map do |runner|
      Runner.new(
        name: runner.name,
        labels: runner.labels.map(&:name),
        description: "#{image_name_for(runner, current_repository.owner)} · #{runner.machine_spec.display_title}",
        os: normalize_os(runner.platform.split("-").first),
        source: runner.inherited? ? "Enterprise" : "Organization",
      )
    end
  end

  sig { returns(T::Array[Runner]) }
  def fetch_shared_runners
    owner = current_repository.owner
    return [] unless owner.organization?
    return [] unless can_use_org_runners?(owner)

    runners = T.let([], T::Array[T.any(Actions::Runner, Actions::RunnerScaleSet)])
    can_use_actions_team_features = current_repository.owner_can_use_actions_team_features?

    Actions::RunnerGroup.for_entity(
      current_repository,
      include_runners: true,
      include_runner_scale_sets: true,
      include_hosted_runner_groups: false,
    ).each do |group|
      default_group = group.default?

      group.runner_scale_sets.each do |scale_set|
        next unless can_use_actions_team_features || default_group
        scale_set.inherited = group.inherited?
        runners.append(scale_set)
      end

      group.runners.each do |runner|
        next unless can_use_actions_team_features || default_group
        runner.inherited = group.inherited?
        runners.append(runner)
      end
    end

    runners.map do |runner|
      source = runner.inherited? ? "Enterprise" : "Organization"
      map_to_runner_list_item(runner, source:)
    end
  end

  sig { returns(T::Array[Runner]) }
  def fetch_repository_scale_sets
    Actions::RunnerScaleSet.for_entity(current_repository).map { |scale_set| map_to_runner_list_item(scale_set, source: "Repository") }
  end

  sig { params(page: Integer, per_page: Integer).returns(T::Array[Runner]) }
  def paginated_repository_self_hosted_runners(page: 1, per_page: 100)
    use_runner_admin = use_runner_admin?(current_repository)
    resp = list_runners_helper(current_repository, page: page, per_page: per_page, use_runner_admin: use_runner_admin, do_experiment: do_runner_admin_experiment?(current_repository))

    Actions::Runner.from_rpc_collection(Array(resp.value&.runners), owner: current_repository, using_runner_admin: use_runner_admin).map do |runner|
      map_to_runner_list_item(runner, source: "Repository")
    end
  end

  sig { returns(T::Boolean) }
  def has_hosted_runner_group?
    owner = current_repository.owner
    # Individual users always have access to GitHub-hosted runners
    return true unless owner.organization?

    runner_groups = Actions::RunnerGroup.for_entity(owner, include_hosted_runner_groups: true)
    runner_groups.any? { |group| group.hosted? && !group.inherited? }
  end

  sig { returns(T.nilable(String)) }
  def set_up_runners_path
    return nil unless (owner = current_repository.owner)

    if (business = owner.business)
      settings_actions_runners_enterprise_path(business) if business.adminable_by?(current_user)
    elsif owner.organization?
      settings_org_actions_runners_path(owner) if owner.adminable_by?(current_user)
    end
  end

  sig { returns(T::Boolean) }
  def show_larger_runner_banner?
    owner = current_repository.owner.business || current_repository.owner
    return false if owner.feature_enabled?(:opt_out_of_action_upsells)
    return false if fetch_larger_runners.any?

    true
  end

  private

  sig { params(runner: T.any(Actions::Runner, Actions::RunnerScaleSet), source: String).returns(Runner) }
  def map_to_runner_list_item(runner, source:)
    description = case runner
    when Actions::Runner # Self-hosted runners
      "#{runner.os} · #{runner.arch} · Self-hosted"
    when Actions::RunnerScaleSet
      "Runner group: #{runner.group_name}"
    else
      T.absurd(runner)
    end

    Runner.new(
      name: runner.name,
      labels: runner.labels.map(&:name),
      description: description,
      os: normalize_os(runner.os),
      source: source,
    )
  end

  sig { params(os: String).returns(String) }
  def normalize_os(os)
    return "windows" if os == "win"

    os.downcase
  end
end
