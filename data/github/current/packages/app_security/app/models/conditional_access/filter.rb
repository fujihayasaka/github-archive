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
    include AuthzdActor
    include AuthzdTestHelper
    include AuthzdRollout

    Error = Class.new(StandardError)
    AuthzdServerError = Class.new(Error)

    PROTO_VISIBILITY_MAP = {
      VISIBILITY_PRIVATE: :private,
      VISIBILITY_PUBLIC: :public,
      VISIBILITY_INTERNAL: :internal,
      VISIBILITY_UNKNOWN: :unknown,
    }

    PROTO_OUTCOME_MAP = {
      INAPPLICABLE: :inapplicable,
      UNSATISFIED: :unsatisfied,
      SATISFIED: :satisfied,
    }

    attr_reader :callback, :target_provider, :do_authzd_science

    # callback is used so that policies can perform context specific operations the filter cannot do itself,
    # i.e. retrieving user from the controller request, session, rendering of templates...
    def initialize(callback, do_authzd_science: false)
      @callback = callback
      @target_provider = ConditionalAccess::TargetProvider.new(location: location, callback_name: callback_name)
      @do_authzd_science = do_authzd_science
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
      rescue StandardError => ex # rubocop:disable Lint/RescueException
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

    def self.clean_science_result(actual, expected)
      # build a subset of actual where actual differs from expected
      diff = {}
      actual.each do |key, value|
        if !expected&.key?(key) || value != expected[key]
          diff[key] = value
        end
      end

      # remove extra details from mismatches
      cleaned = {}
      diff.each do |target, outcomes|
        clean_target = if target == :no_target_for_conditional_access
          { type: "no_target_for_conditional_access", id: 0 }
        else
          { type: target&.class&.name, id: target&.id }
        end
        cleaned[clean_target] = outcomes
      end
      cleaned
    end

    def authzd_cap_actor
      respond_to?(:actor) ? actor : nil
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
      authzd_tag = "unknown"
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

          prefill_multiple_resource_visibility(resources)
          resources_to_target = safe_multiple_targets_for_conditional_access(resources)
          all_targets = resources_to_target.values.uniq

          # { target => { policy => visibility => { outcome }}}
          target_to_policy_outcomes = if use_authzd_cap_filter?
            authzd_tag = "true"
            target_to_policy_outcomes_authzd(all_targets, policies)
          elsif run_authzd_cap_experiment?
            authzd_tag = "experiment"
            compare_authzd_cap(all_targets, policies)
          else
            authzd_tag = "false"
            target_to_policy_outcomes_control(all_targets, policies)
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
      rescue StandardError => ex
        raise
      ensure
        end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        tags = ["location:#{location}", "callback:#{callback_name}", "authzd:#{authzd_tag}", "success:#{ex.nil?}", "error:#{ex&.class&.name}"]
        GitHub.dogstats.distribution("cap.filter.evaluation.dist", (end_time - start_time) * 1_000, tags: tags)
      end
    end

    def compare_authzd_cap(all_targets, policies)
      comparison_policies = policies & authzd_science_policies
      candidate_result = control_result = candidate_error = control_error = nil
      targets_by_type_count = all_targets.group_by { |t| t.class.name }.transform_values(&:size)

      experiment_name = "authzd_cap_filter_#{location}"
      science_class = GitHub.multi_tenant_enterprise? ? ProximaScientist : Scientist

      control_result = nil
      control_error  = nil

      begin
        control_result = target_to_policy_outcomes_control(all_targets, policies)
      rescue StandardError => ex
        control_error = ex
      end

      science_class.run experiment_name do |e|
        e.use do
          raise control_error if control_error
          control_result
        end
        e.try do
          begin
            candidate_result = target_to_policy_outcomes_authzd(all_targets, comparison_policies)
          rescue StandardError => ex
            candidate_error = ex
            raise
          end
        end
        e.run_if { comparison_policies.any? }

        e.clean do |result|
          next result if result.nil?

          if result.equal?(candidate_result)
            if control_error
              "result omitted due to control error"
            else
              ::ConditionalAccess::Filter.clean_science_result(result, control_result)
            end
          elsif result.equal?(control_result)
            if candidate_error
              "result omitted due to candidate error, total targets: #{all_targets.size}, counts by class: #{targets_by_type_count}"
            else
              ::ConditionalAccess::Filter.clean_science_result(result, candidate_result)
            end
          else
            result # should not get here, but just in case
          end
        end
        e.context targets_by_type_count: targets_by_type_count, targets_count: all_targets.size
        e.compare do |control, candidate|
          science_control = {}
          science_candidate = {}
          control.each do |target, outcomes|
            comparable_outcomes = outcomes.select do |policy, _results|
              comparison_policies.include?(policy)
            end

            science_control[target] = comparable_outcomes
          end

          # remove the external cap policy results from matching
          # in cases where we expect a mismatch due to the faked token refresh in authzd
          candidate.each do |target, outcomes|
            comparable_outcomes = outcomes.select do |policy, _results|
              comparison_policies.include?(policy)
            end
            control_excap = science_control[target]&.dig(:external_conditional_access_policy, :private)
            candidate_excap = comparable_outcomes.dig(:external_conditional_access_policy, :private)
            if control_excap == :satisfied && candidate_excap == :unsatisfied
              science_control[target].delete(:external_conditional_access_policy)
              comparable_outcomes.delete(:external_conditional_access_policy)
            end

            science_candidate[target] = comparable_outcomes
          end

          is_match = (science_control == science_candidate)
          tags = ["match:#{is_match}", "filter:#{location}"]

          # if we're using the custom ProximaScientist class, we won't have
          # the Scientist UI tooling with all of the context about mismatches
          # so for now we'll just log as much as we can here
          # the log automatically has the request ID, which can help us diagnose further if needed
          if !is_match && GitHub.multi_tenant_enterprise?
            candidate_diff = if candidate_error
              "result omitted due to candidate error"
            else
              ::ConditionalAccess::Filter.clean_science_result(candidate, control)
            end
            control_diff = if control_error
              "result omitted due to control error"
            else
              ::ConditionalAccess::Filter.clean_science_result(control, candidate)
            end
            GitHub.logger.info(
              "Mismatch in authzd cap experiment",
              "code.function" => "compare_authzd_cap",
              "authzd.cap.experiment_name" => experiment_name,
              "authzd.cap.location" => location,
              "authzd.cap.callback" => callback_name,
              "authzd.cap.policies" => "#{policies}",
              "authzd.cap.comparison_policies" => "#{comparison_policies}",
              "authzd.cap.candidate_diff" => candidate_diff,
              "authzd.cap.control_diff" => control_diff,
              "authzd.cap.targets_count" => all_targets.size,
              "authzd.cap.targets_by_type_count" => targets_by_type_count,
            )
          end

          # Add tags for policies with equivalent results
          begin
            match_by_policy = comparison_policies.map { |p| [p, nil] }.to_h
            science_control.each do |target, control_outcomes|
              cand_outcomes = candidate[target] || {}

              comparison_policies.each do |policy|
                next if policy == :external_conditional_access_policy
                target_policy_match = cand_outcomes[policy] == control_outcomes[policy]
                if match_by_policy[policy].nil?
                  match_by_policy[policy] = target_policy_match
                else
                  match_by_policy[policy] = match_by_policy[policy] && target_policy_match
                end
              end
            end

            match_by_policy.each do |policy, is_match|
              tags << "#{policy}:#{is_match ? "match" : "mismatch" }"
            end
            GitHub.dogstats.count("cap_extraction_filter_experiment_result", 1, tags: tags)
          rescue StandardError
            # we can still stat the match and enforcer tags here in the case where
            # we may have caused an exception in the block above calculating the more detailed tags
            GitHub.dogstats.count("cap_extraction_filter_experiment_result", 1, tags: tags)
          end

          is_match
        end
      end
    end

    def target_to_policy_outcomes_control(all_targets, policies)
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
        targets_by_class.each do |target_class, targets|
          # Targets are either User, Organiztions or Businesses and used to evaluate the policies
          prefill_multiple_target(targets, target_class)
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

      target_to_policy_outcomes
    end

    # Returns the set of policies that should be compared to their authzd implementations. This should be overridden in subclasses.
    #
    # returns an array of policy name symbols.
    def authzd_science_policies
      []
    end

    def run_authzd_cap_experiment?
      # run_authzd_cap_filter_experiment will be enabled 100% or 0%
      # participation rate by location is controlled by the location flag (ex 1% of api, 10% of web)
      # note - authzd cap policies don't support Proxima yet
      location_flag = "run_authzd_cap_filter_experiment_#{location}".to_sym
      do_authzd_science \
        && FeatureFlag.vexi.enabled?(:run_authzd_cap_filter_experiment, default: false) && FeatureFlag.vexi.enabled?(location_flag, default: false)
    end

    def target_to_policy_outcomes_authzd(all_targets, policies)
      target_to_policy_outcomes = Hash.new { |h, k| h[k] = Hash.new { |h2, k2| h2[k2] = {} } }
      @authzd_results_cache ||= Hash::new { |h, k| h[k] = Hash.new { |h2, k2| h2[k2] = {} } }
      uncached_targets = Set.new
      uncached_policies = Set.new

      # Iterate over (targets x policies) to either:
      # * Read results from the cache
      # * Add them to the list of resources pending for evaluation (targets_by_policy_and_class)
      all_targets.each do |target|
        policies.each do |policy|
          cached_value = @authzd_results_cache[target][policy]
          if cached_value.nil? || cached_value.empty?
            uncached_targets << target
            uncached_policies << policy
          else
            target_to_policy_outcomes[target][policy] = cached_value
          end
        end
      end

      if uncached_targets.empty? || uncached_policies.empty?
        return target_to_policy_outcomes
      end

      # Cached results for a policy/target will only spare execution if they are complete for the entire policy/target (no partial caching)
      # This differs from the monolith behavior, but authzd does not support targets-per-policy in a single filter request
      results = authzd_evaluate_policies(uncached_targets, uncached_policies.to_a)
      results.each do |target_result|
        target = uncached_targets.find do |t|
          next true if t == :no_target_for_conditional_access || target_result.type&.to_sym == :no_target_for_conditional_access
          t.id == target_result.id && t.class.name == target_result.type.to_s
        end

        policy_groups = target_result.results.group_by { |r| r.policy&.to_sym }
        policy_groups.each do |policy, policy_results|
          outcome_hash = policy_results.map do |pr|
            [PROTO_VISIBILITY_MAP[pr.visibility], PROTO_OUTCOME_MAP[pr.outcome]]
          end.to_h
          target_to_policy_outcomes[target][policy] = outcome_hash # CAPTODO - update to ||= to use cached values? See if mismatches come from this behavior difference
          @authzd_results_cache[target][policy] = outcome_hash
        end
      end

      success = true
      target_to_policy_outcomes
    end

    # what attributes should be sent to authzd?
    def authzd_cap_request_attributes
      raise Error, "#{self.class} must implement authzd_cap_request_attributes method"
    end

    def authzd_evaluate_policies(targets, policies)
      attrs = resolve_attributes(policies)

      authzd_attrs = attrs.map do |k, v|
        Authzd::Proto::Attribute.wrap(k, v)
      end
      authzd_targets = targets.map do |t|
        if t == :no_target_for_conditional_access
          Authzd::CapEvaluator::Target.new({
            id: 0,
            type: "no_target_for_conditional_access",
            visibilities: []
          })
        else
          Authzd::CapEvaluator::Target.new({
            id: t.id,
            type: t.class.name,
            visibilities: [
              Authzd::CapEvaluator::Visibility::VISIBILITY_PRIVATE,
              Authzd::CapEvaluator::Visibility::VISIBILITY_PUBLIC,
              Authzd::CapEvaluator::Visibility::VISIBILITY_INTERNAL,
            ]
          })
        end
      end

      headers = {}
      headers["X-Github-Features"] = github_features_header(targets) if Rails.env.test? # rubocop:disable GitHub/DoNotBranchOnRailsEnv
      headers["X-Github-Capabilities"] = github_capabilities_header if Rails.env.test? # rubocop:disable GitHub/DoNotBranchOnRailsEnv
      authz_request = Authzd::CapEvaluator::FilterRequest.new(attributes: authzd_attrs, targets: authzd_targets)


      cap_results = GitHub.tracer.in_span("Authzd.conditional_access_client.evaluate_policies_for_filtering",
        attributes: {
          GitHub::TaggingHelper::CATALOG_SERVICE_TAG => "github/conditional_access",
          "code.function" => __method__.to_s,
          "code.namespace" => self.class.name,
          "cap.callback" => callback_name,
          "cap.location" => location.to_s,
        }, kind: :internal) do
        Authzd.conditional_access_client.evaluate_policies_for_filtering(authz_request, headers)
      end

      if cap_results.error
        raise AuthzdServerError.new("Authzd CAP filtering failed: #{cap_results.error}")
      end

      cap_results.data.results
    rescue Faraday::Error, AuthzdServerError => err
      GitHub.dogstats.increment("cap.filter.authzd_request.failure", tags: ["location:#{location}", "callback:#{callback_name}"])
      filter_err = ConditionalAccess::Filter::Error.new(err)
      Failbot.report!(filter_err)
      # there's no sensible way to handle an error from authzd here
      # we _could_ return a hash where all policies are unsatisfied,
      # but that would be a lie. So we reraise the error
      raise filter_err
    end

    def resolve_attributes(policies)
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      attrs = authzd_cap_actor_attributes
      attrs = attrs.merge(authzd_cap_request_attributes)
      attrs = attrs.merge(authzd_cap_dotcom_ci_attributes) if Rails.env.test? # rubocop:disable GitHub/DoNotBranchOnRailsEnv

      attrs["conditional.access.science_policies"] = policies

      if GitHub.multi_tenant_enterprise? && tenant = GitHub::CurrentTenant.get
        attrs["conditional.access.tenant.id"] = tenant.id
      end

      attrs
    ensure
      end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      tags = ["location:#{location}", "callback:#{callback_name}"]
      GitHub.dogstats.distribution("cap.filter.resolve_attributes.dist", (end_time - T.must(start_time)) * 1_000, tags: tags)
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

    # helper method to preload associations that are needed for the policies to avoid N+1 queries
    def prefill_multiple_target(targets, target_class)
      if target_class == Organization
        GitHub::PrefillAssociations.prefill_associations(targets, :business)
      end
    end

    def prefill_multiple_resource_visibility(resources)
      repos_with_internal_not_loaded = resources.filter { |resource| resource.is_a?(Repository) && !resource.association(:internal_repository).loaded? }
      GitHub::PrefillAssociations.prefill_associations(repos_with_internal_not_loaded, :internal_repository)
    end
  end
end
