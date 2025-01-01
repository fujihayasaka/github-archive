# typed: strict
# frozen_string_literal: true

# This class allows SecurityProducts to check any preconditions they may have on a Repository's
# available runner groups.
#
# It makes best effort to cache requests to the Actions service domain so it is safe to use
# during bulk enablement where multiple SecurityProducts may need to inspect the runner pool.
module SecurityProductsEnablement::Actions
  class RunnerChecker
    extend T::Sig
    include GitHub::Memoizer

    sig { returns(Repository) }
    attr_reader :repository

    sig { params(repository: Repository).void }
    def initialize(repository)
      @repository = repository
    end

    sig { params(desired_labels: T::Array[String]).returns(T::Boolean) }
    def labelled_runners_available?(desired_labels:)

      if repository.owner_can_use_larger_cloud_hosted_runners?
        return true if cloud_hosted_runners.any? { |runner| check_labels(runner_object: runner, desired_labels:) }
      end

      # Only org-owned repos have access to runner groups
      if repository.owner&.organization?
        # First check if any runners in any runner groups have the right label.
        includes_desired_labels = runner_groups.any? do |runner_group|
          runner_group.runners.any? do |runner|
            check_labels(runner_object: runner, desired_labels:)
          end
        end

        return true if includes_desired_labels

        # Next check if any runner scale sets in any runner groups have the right label.
        includes_desired_labels = runner_groups.any? do |runner_group|
          runner_group&.runner_scale_sets&.any? do |runner_scale_set|
            check_labels(runner_object: runner_scale_set, desired_labels:)
          end
        end

        return true if includes_desired_labels
      end

      # Next check runners individually assigned to this repository.
      includes_desired_labels = individual_runners.any? do |runner|
        check_labels(runner_object: runner, desired_labels:)
      end

      return true if includes_desired_labels

      includes_desired_labels = individual_runner_scale_sets.any? do |runner_scale_set|
        check_labels(runner_object: runner_scale_set, desired_labels:)
      end

      return true if includes_desired_labels

      false
    end

    private

    sig { returns(T::Array[T.untyped]) }
    memoize def cloud_hosted_runners
      ::Actions::LargerRunner.larger_runners_for(entity: repository, owner: repository.organization)
    end

    sig { returns(T::Array[T.untyped]) }
    memoize def runner_groups
      ::Actions::RunnerGroup.for_entity(
        repository,
        include_runners: true,
        include_hosted_runner_groups: true,
        include_runner_scale_sets: true,
      )
    end

    # NOTE: If this Twirp call fails, we will not retry it on subsequent checks within a single enablement event, this
    #       seems like better behaviour than hammering a service that may be throttling or down. Since a single
    #       precondition failing will prevent a Security Configuration attaching, the end behaviour is the same.
    sig { returns(T.untyped) }
    memoize def individual_runners
      resp = ::Launch::Twirp.self_hosted_runners_client.list_runners(repository)
      if resp.call_succeeded?
        resp.value.runners
      else
        []
      end
    end

    sig { returns(T::Array[T.untyped]) }
    memoize def individual_runner_scale_sets
      ::Actions::RunnerScaleSet.for_entity(repository)
    end

    sig { params(runner_object: T.untyped, desired_labels: T::Array[String]).returns(T::Boolean) }
    def check_labels(runner_object:, desired_labels:)
      runner_object.labels.map(&:name).to_set.superset?(desired_labels.to_set)
    end
  end
end
