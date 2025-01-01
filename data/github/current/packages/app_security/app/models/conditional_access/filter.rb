# typed: false
# frozen_string_literal: true

# Conditional Access filtering is the process where one or more
# application business objects are evaluated against a set of conditional access
# rules defined by a governing entity known as the "target for conditional access"
# (e.g. Organization owning a Repository).
#
# Filtering is generally necessary when application logic deals not with one but multiple
# governing entities. A prime example would be GitHub notifications, where each notification
# could belong to different targets for conditional access, with different set of conditional access policies.
#
# ConditionalAccess::Filter builds on top of ConditionalAccess::Enforcer and reuses
# its workflow to implement the filtering process. Contrary to enforcement, filtering
# does not have any enforcement side effect.
module ConditionalAccess
  class Filter
    include Scientist

    Error = Class.new(StandardError)

    attr_reader :callback, :target_provider

    # callback is used so that policies can perform context specific operations the filter cannot do itself,
    # i.e. retrieving user from the controller request, session, rendering of templates...
    def initialize(callback)
      @callback = callback
      @target_provider = ConditionalAccess::TargetProvider.new(location: location, callback_name: callback_name)
    end

    # Given an Enumerable or Object of ApplicationRecords, evaluates the conditional access policies and returns
    # the results
    #
    # only: is a policy symbol or array of symbols to evaluate. This is added for convenience during the migration
    #       because many callsites do not use all policies yet
    # exclude: is a policy symbol or array of symbols to ignore on evaluation. Takes precedence over "only".
    #          This is added for convenience during the migration because many callsites do not use all policies yet
    # resources: Enumerable or Object of ApplicationRecords to authorize
    #
    # returns: ConditionalAccess::ResultSet with the outcome of evaluating the filter against the provided resources
    def evaluate(resources, only: nil, exclude: nil)
      begin
        return ConditionalAccess::ResultSet::new([]) if resources.blank?

        resources = Array.wrap(resources) unless resources.is_a?(Enumerable)
        evaluated_resources = ActiveRecord::Base.connected_to(role: :reading) do
          perform_filter(resources, policies: calculate_policies(only, exclude))
        end

        ConditionalAccess::ResultSet::new(evaluated_resources)
      rescue StandardError => ex # rubocop:disable Lint/GenericRescue
        raise
      ensure
        GitHub.dogstats.count("cap.filter.executed", 1, tags: ["success:#{ex.nil?}", "error:#{ex&.class&.name}"])
      end
    end

    # Shorthand for evaluate(...).unauthorized
    # Returns a ResultSet containing resources that was "unsatisfied" for any one of the conditional access policies
    def unauthorized(resources, only: nil, exclude: nil)
      evaluate(resources, only: only, exclude: exclude).unauthorized
    end

    # Shorthand for evaluate(...).authorized
    # Returns a ResultSet containing resources that were any of "unenforceable/inapplicable/satisfied" on all of the conditional access policies
    def authorized(resources, only: nil, exclude: nil)
      evaluate(resources, only: only, exclude: exclude).authorized
    end

    # Shorthand for evaluate(...).unauthorized.resources
    # Returns an Array of resources that was "unsatisfied" for any one of the conditional access policies
    def unauthorized_resources(resources, only: nil, exclude: nil)
      unauthorized(resources, only: only, exclude: exclude).resources
    end

    # Shorthand for evaluate(...).authorized.resources
    # Returns an Array of resources that were any of "unenforceable/inapplicable/satisfied" on all of the conditional access policies
    def authorized_resources(resources, only: nil, exclude: nil)
      authorized(resources, only: only, exclude: exclude).resources
    end

    # Shorthand for evaluate(...).unauthorized.resources.pluck(:id)
    # Returns an Array of integers representing IDs for resources that were "unsatisfied" for any one of the conditional access policies
    def unauthorized_resource_ids(resources, only: nil, exclude: nil)
      unauthorized_resources(resources, only: only, exclude: exclude).pluck(:id)
    end

    # Shorthand for evaluate(...).authorized.resources.pluck(:id)
    # Returns an Array of integers representing IDs for resources that were any of "unenforceable/inapplicable/satisfied" for all the conditional access policies
    def authorized_resource_ids(resources, only: nil, exclude: nil)
      authorized_resources(resources, only: only, exclude: exclude).pluck(:id)
    end

    # Returns an Array of resources that were "satisfied" for all of the conditional access policies
    # Bear in mind this refers exclusively to the "satisfied" outcome of the policy evaluation. This is a subset
    # from what "authorized" style methods return. This method won't return as satisfied any resource
    # that had as outcome "unenforceable", "inapplicable" nor "unsatisfied".
    def satisfied_resources(resources, only: nil, exclude: nil)
      evaluate(resources, only: only, exclude: exclude)
      .results
      .filter { |result| result.satisfied? }
      .map { |result| result.resource }
    end

    # raises if an enumerable contains objects with classes other than the provided class
    def self.ensure_with_class(enumerable, klass)
      if enumerable.respond_to?(:klass)
        raise ArgumentError, "argument includes objects other than #{klass.name}" unless enumerable.klass == klass
      else
        raise ArgumentError, "argument includes objects other than #{klass.name}" unless (enumerable.map { |element| element.class } - [klass]).empty?
      end
    end

    # Given an enumerable of resources, efficiently and securely computes their targets for conditional access (TFCA).
    # Target for conditional access is the entity governing resources that are subject to conditional access policies.
    #
    # Examples:
    # - Organization is the TFCA for an org-owned repository
    # - User is the TFCA for a user-owned repository
    #
    # resources - an enumerable of resources to compute their target for conditional access. These objects must
    #             implement a "multiple_target_for_conditional_access" class method that receives an enumerable of
    #             instances of that particular class, and returns a Hash[class_instance] => TFCA
    #
    # returns Hash[resource] => TFCA
    def safe_multiple_targets_for_conditional_access(resources)
      @tfca_cache ||= {}

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      raise ConditionalAccess::Filter::Error.new("expected Enumerable") unless resources.is_a?(Enumerable)

      # Iterate over each resource to either
      # * Find it's TFCA in the cache
      # * Or, put it in the list to be resolved
      resources_to_targets = {}
      targets_by_class = Hash::new { |h, k| h[k] = [] }
      resources.each do |r|
        cached_target = @tfca_cache[r]
        if cached_target.nil?
          targets_by_class[r.class] << r
        else
          resources_to_targets[r] = cached_target
        end
      end

      targets_by_class.each do |resource_class, resources|
        unless resource_class.respond_to?(:multiple_target_for_conditional_access, true)
          raise ConditionalAccess::Filter::Error.new("#{resource_class} does not implement multiple_target_for_conditional_access")
        end
        targets = resource_class.multiple_target_for_conditional_access(resources)

        if targets.has_value?(nil)
          raise ConditionalAccess::Filter::Error.new("#{resource_class.name}#multiple_target_for_conditional_access returned a nil value. nil is not a valid target for conditional access, only User/Organization/Business are allowed")
        end

        resources_to_targets.merge!(targets)
        @tfca_cache.merge!(targets)
      end

      # this creates a new hash that has the same order as input resources argument
      # raises if resources_to_targets values don't match the passed resources
      resources.each_with_object({}) do |v, h|
        h[v] = resources_to_targets.fetch(v) do |missing_resource|
          raise ConditionalAccess::Filter::Error.new("could not determine target for conditional access for #{missing_resource.class.name} #{missing_resource.id}")
        end
      end
    ensure
      end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      tags = ["location:#{location}", "callback:#{callback_name}"]
      GitHub.dogstats.distribution("cap.multiple_target_for_conditional_access.dist", (end_time - start_time) * 1_000, tags: tags)
    end

    private

    # only take public and internal into consideration if the callback is a read request
    # might need to check for more ways to determine if the request is a read request
    def safe_request_method?
      callback.respond_to?(:read_request?) && callback.send(:read_request?)
    end

    # New Resource filtering logic. This implementation enables the filter to take the visibility of the resource into consideration
    #
    # The workflow is:
    # 1. determine the targets for conditional access of the input resources
    # 2. determine the applicability of every policy over every TFCA
    # 3. determine the satisfiability of every policy over every TFCA with the resource visibility
    def perform_filter(resources, policies: conditional_access_policies)
      @results_cache_with_visibility ||= Hash::new { |h, k| h[k] = Hash.new { |h2, k2| h2[k2] = {} } }

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      raise ConditionalAccess::Filter::Error.new("expected Enumerable") unless resources.is_a?(Enumerable)
      begin
        GitHub.tracer.in_span("ConditionalAccess::Filter#perform_filter",
                                attributes: {
                                  GitHub::TaggingHelper::CATALOG_SERVICE_TAG => "github/conditional_access",
                                  "code.function" => __method__.to_s,
                                  "code.namespace" => self.class.name,
                                  "cap.resourceCount" => resources.size,
                                  "cap.location" => location.to_s,
                                  "cap.callback" => callback_name,
                                  "cap.control" => false, # adding this to the span to make it easier to track the new implementation
                                }, kind: :internal) do |span|

          raise ConditionalAccess::Filter::Error, "no policies defined" if policies.empty?

          conditional_access_policies.each { |policy| span.set_attribute("cap.policy_#{policy}", true) }

          resources_to_target = safe_multiple_targets_for_conditional_access(resources)
          all_targets = resources_to_target.values.uniq
          # { target => { policy => visibility => { outcome }}}
          target_to_policy_outcomes = Hash.new { |h, k| h[k] = Hash.new { |h2, k2| h2[k2] = {} } }
          targets_by_policy_and_class = Hash::new { |h, k| h[k] = Hash::new { |h2, k2| h2[k2] = [] } }

          # Iterate over (targets x policies) to either:
          # * Read results from the cache
          # * Add them to the list of resources pending for evaluation (targets_by_policy_and_class)
          all_targets.each do |target|
            policies.each do |policy|
              cached_value = @results_cache_with_visibility[target][policy]
              if cached_value.nil? || cached_value.empty?
                targets_by_policy_and_class[policy][target.class] << target
              else
                target_to_policy_outcomes[target][policy] = cached_value
              end
            end
          end

          # Evaluate the workflow for policy-target combinations that haven't been yet cached.
          targets_by_policy_and_class.each do |policy, targets_by_class|
            targets_by_class.values.each do |targets|
              # evaluate workflow steps
              applicable_targets = multiple_applicable(targets, policy)
              inapplicable_targets = targets - applicable_targets

              if applicable_targets.empty?
                evaluated_targets = {}
                unevaluated_targets = []
              else
                # return is Hash{target => Hash{visibility => decision}}
                evaluated_targets = multiple_satisfied(applicable_targets, policy)
                unevaluated_targets = applicable_targets - evaluated_targets.keys
              end

              # we can keep the inapplicable targets
              # we then need to iterate over the evaluated targets and match the visibility to the outcome

              # intermediate structure compute the resulting ConditionalAccess::Result
              inapplicable_targets.each do |inapplicable_target|
                target_to_policy_outcomes[inapplicable_target][policy] = { "private": :inapplicable }
                @results_cache_with_visibility[inapplicable_target][policy] = { "private": :inapplicable }
              end
              evaluated_targets.each do |target, outcome|
                target_to_policy_outcomes[target][policy] = outcome
                @results_cache_with_visibility[target][policy] = outcome
              end
              # This is a fallback, if we can't evaluate the policy
              unevaluated_targets.each do |unevaluated_target|
                target_to_policy_outcomes[unevaluated_target][policy] = { "private": :unsatisfied }
                @results_cache_with_visibility[unevaluated_target][policy] = { "private": :unsatisfied }
              end
            end
          end

          # Compute the output ConditionalAccess::Result given the intermediate results
          # This also has the side effect of ensuring that resources stay in the same order
          # even if the intermediate results got out of order, because safe_multiple_targets_for_conditional_access
          # guarantees input order
          resources_to_target.map do |resource, target|
            policy_outcomes = target_to_policy_outcomes[target]
            ConditionalAccess::Result::new(resource, policy_outcomes, safe_request_method: safe_request_method?)
          end
        end
      ensure
        end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        tags = ["location:#{location}", "callback:#{callback_name}"]
        GitHub.dogstats.distribution("cap.filter.evaluation.dist", (end_time - start_time) * 1_000, tags: tags)
      end
    end

    # determines if the argument policy is applicable over each one of the provided targets
    #
    # targets - an enumerable of targets for conditional access
    # policy - a symbol representing the policy to evaluate
    #
    # returns an enumerable of targets for which the policy is applicable
    def multiple_applicable(targets, policy)
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      method = "multiple_#{policy}_applicable".to_sym

      GitHub.tracer.in_span("#{method}",
                            attributes: {
                              GitHub::TaggingHelper::CATALOG_SERVICE_TAG => "github/conditional_access",
                              "code.function" => __method__.to_s,
                              "code.namespace" => self.class.name,
                              "cap.callback" => callback_name,
                              "cap.location" => location.to_s,
                              "cap.operation" => "applicable",
                              "cap.policy" => "#{policy}",
                              "cap.targetCount" => targets.size,
                            }, kind: :internal) do |_span|

        next targets unless respond_to?(method, true)
        send(method, targets, target_provider)
      end
    ensure
      end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      tags = ["policy:#{policy}", "location:#{location}", "callback:#{callback_name}", "operation:applicable"]
      GitHub.dogstats.distribution("cap.filter.operation.dist", (end_time - start_time) * 1_000, tags: tags)
    end

    # determines if the argument policy is satisfied over each one of the provided targets
    #
    # targets - an enumerable of targets for conditional access
    # policy - a symbol representing the policy to evaluate
    #
    # returns an enumerable of targets for which the policy is sastisfied
    def multiple_satisfied(targets, policy)
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      method = "multiple_#{policy}_satisfied".to_sym

      GitHub.tracer.in_span("#{method}",
                            attributes: {
                              GitHub::TaggingHelper::CATALOG_SERVICE_TAG => "github/conditional_access",
                              "code.function" => __method__.to_s,
                              "code.namespace" => self.class.name,
                              "cap.callback" => callback_name,
                              "cap.location" => location.to_s,
                              "cap.operation" => "satisfied",
                              "cap.policy" => "#{policy}",
                              "cap.targetCount" => targets.size,
                            }, kind: :internal) do |_span|
        unless respond_to?(method, true)
          next {}
        end
        send(method, targets, target_provider)
      end
    ensure
      end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      tags = ["policy:#{policy}", "location:#{location}", "callback:#{callback_name}", "operation:satisfied"]
      GitHub.dogstats.distribution("cap.filter.operation.dist", (end_time - start_time) * 1_000, tags: tags)
    end

    # Returns the set of policies by which to filter. Classes including this method should define the policies to filter.
    #
    # returns returns an array of symbols that identify the policies to filter
    def conditional_access_policies
      raise Error, "#{self.class} must implement conditional_access_policies method"
    end

    # returns the name of the callback
    def callback_name
      cb = callback
      return cb.name if cb.is_a?(Class)
      cb.class.name
    end

    # helper method to support "only/exclude" semantics, to help filter executing only certain policies,
    # and fallback to all policies otherwise. Needed because not every callsite takes into consideration
    # every policy
    def calculate_policies(only, exclude)
      return Array(only) - Array(exclude) if only.present?
      conditional_access_policies - Array(exclude)
    end
  end
end
