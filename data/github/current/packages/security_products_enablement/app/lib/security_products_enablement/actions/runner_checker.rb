# typed: strict
# frozen_string_literal: true

# This class allows SecurityProducts to check any preconditions they may have on a Repository's
# available runner groups.
#
# It makes best effort to cache requests to the Actions service domain so it is safe to use
# during bulk enablement where multiple SecurityProducts may need to inspect the runner pool.
module SecurityProductsEnablement::Actions
  class RunnerChecker
    include GitHub::Memoizer
    include Actions::RunnersClientHelper

    sig { returns(T.any(Business, Organization, Repository)) }
    attr_reader :entity

    sig { params(entity: T.any(Business, Organization, Repository)).void }
    def initialize(entity)
      @entity = entity
    end

    sig { params(desired_labels: T::Array[String], calling_context_only_for_metrics: Symbol).returns(T::Boolean) }
    def labelled_runners_available?(desired_labels:, calling_context_only_for_metrics: :unknown)
      desired_labels = desired_labels.to_set

      GitHub.dogstats.distribution_time("security_products.labelled_runners_available.time", tags: ["context:#{calling_context_only_for_metrics}"]) do
        # use lazy chaining of enumerators to avoid work if we find an early match
        # we do not return enumerators from the methods themselves as they are memoized and the enumerators
        # would be consumed after the first read
        result = cloud_hosted_runners.lazy.chain(
          Enumerator.new { |y| runner_groups.flat_map(&:runners).each(&y.to_proc) },
          Enumerator.new { |y| runner_groups.flat_map(&:runner_scale_sets).each(&y.to_proc) },
          Enumerator.new { |y| individual_runners.each(&y.to_proc) },
          Enumerator.new { |y| individual_runner_scale_sets.each(&y.to_proc) },
        ).any? do |source|
          source.labels.map(&:name).to_set.superset?(desired_labels)
        end
      end
    end

    sig { returns(T::Array[String]) }
    def labels
      cloud_hosted_runners.chain(
        runner_groups.flat_map(&:runners),
        runner_groups.flat_map(&:runner_scale_sets),
        individual_runners,
        individual_runner_scale_sets
      ).flat_map(&:labels).map(&:name).uniq.to_a
    end

    private

    sig { returns(T::Boolean) }
    def entity_can_use_larger_runners?
      return @entity.owner_can_use_larger_cloud_hosted_runners? if @entity.is_a?(Repository)
      @entity.can_use_larger_runners?
    end

    sig { returns(T::Array[Actions::LargerRunner]) }
    memoize def cloud_hosted_runners
      return [] unless entity_can_use_larger_runners?
      ::Actions::LargerRunner.larger_runners_for(entity: @entity)
    end

    sig { returns(T::Array[Actions::RunnerGroup]) }
    memoize def runner_groups
      if (@entity.is_a?(Repository) && @entity.owner&.organization?) || @entity.is_a?(Organization) || @entity.is_a?(Business)
        ::Actions::RunnerGroup.for_entity(
          @entity,
          include_runners: true,
          include_hosted_runner_groups: true,
          include_runner_scale_sets: true,
        )
      else
        []
      end
    end

    # NOTE: If this Twirp call fails, we will not retry it on subsequent checks within a single enablement event, this
    #       seems like better behaviour than hammering a service that may be throttling or down. Since a single
    #       precondition failing will prevent a Security Configuration attaching, the end behaviour is the same.
    sig { returns(T::Array[GitHub::Launch::Services::Selfhostedrunners::Runner]) }
    memoize def individual_runners
      use_runner_admin = use_runner_admin?(@entity)
      resp = list_runners_helper(@entity, use_runner_admin: use_runner_admin)

      if resp.call_succeeded?
        resp.value.runners.to_a
      else
        []
      end
    end

    sig { returns(T::Array[GitHub::Launch::Services::Runnerscalesets::RunnerScaleSet]) }
    memoize def individual_runner_scale_sets
      ::Actions::RunnerScaleSet.for_entity(@entity)
    end
  end
end
