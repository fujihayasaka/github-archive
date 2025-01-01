# typed: true
# frozen_string_literal: true

# The Conditional Access Framework orchestrates the execution of
# policies that need to be met in order to grant access to an org/business
# owned resource.
#
# The enforcer handles access to a single-resource and executes a side-effect when
# policies are not met. Policies are registered in the enforcer and executed in a predefined order.
#
# The enforcer requires a callback object (i.e. ApplicationController, ApplicationRecord...) that provides access
# in policies to context specific operations (user session? request? request ip? rendering a rails template?)
#
# The enforcer should be invoked in strategic choke-points of the application
module ConditionalAccess
  class Enforcer
    include AuthzdActor
    include AuthzdTestHelper
    include AuthzdRollout

    # Outcomes that are considered "authorized" (i.e. the user should be able to access the resource)
    AUTHORIZED_OUTCOMES = [:satisfied, :inapplicable, :unenforceable]

    # All outcomes
    OUTCOMES = AUTHORIZED_OUTCOMES + [:unsatisfied]

    InvalidPolicyOutcomeError = Class.new(StandardError)

    attr_reader :callback, :target_provider, :do_authzd_science

    # callback is used so that policies can perform context specific operations the enforcer cannot do itself,
    # i.e. retrieving user from the controller request, session, rendering of templates...
    def initialize(callback, do_authzd_science: false)
      @callback = callback
      @target_provider = TargetProvider.new(location: location, callback_name: callback_name)
      @do_authzd_science = do_authzd_science
      @authzd_result_cache = {}
    end

    # Implement a named tracer with a hard-coded name to ensure that all spans emitted by this tracer
    # share the same span operation name. This is useful for aggregating these spans and the trace metrics derived from them,
    # given that this class is used as a superclass elsewhere in the application, which would otherwise casues
    # spans emitted by calls to `tracer.in_span` here to derive the operation name from the class that is inheriting from this one.
    def self.tracer
      @tracer ||= GitHub::Telemetry.tracer("cap_enforcer")
    end

    def tracer
      self.class.tracer
    end

    Error = Class.new(StandardError)
    ResourceError = Class.new(StandardError)
    NilResourceError = Class.new(StandardError)
    NoTargetForConditionalAccessMethodError = Class.new(StandardError)
    AuthzdServerError = Class.new(StandardError)
    EnforcerError = Class.new(StandardError)

    # Evaluates all registered policies and returns all the failed policies.
    # All policies are evaluated in every call unless 'fail_fast' is set
    #
    # This method sequences the execution of all registered policies.
    #
    # Parameters:
    #
    # - resource: the object we want to enforce conditional access to. Must respond to :target_for_conditional_access.
    # - policies: allows overriding the policies to evaluate
    #
    # - fail_fast: if set to true (default is false), returns immediately on the first unsatisfied policy.
    #              The result is still a Hash and will still include all the satisfied policies that were evaluated prior to finding a failing policy.
    #              Failing fast does not take place when policies are inapplicable or unenforceable.
    #
    # The context must implement the following methods to customize the evaluation behaviour:
    # - {policy_id}_enforceable: defines if the policy is enforceable. Used to have classes opt out from a given policy.
    #   If the behaviour is conditional, that must be handled in the applicability phase. It should
    #   be used solely to turn the policy on/off, and it's meant to ease auditability of this opting out.
    #
    # - {policy_id}_applicable: defines if the policy is applicable. This is where conditional logic to determine
    #   if a policy applies to the context or not. Here is were classes usually implement pre-condition checks.
    #
    # - {policy_id}_satisfied: once it has been determined the policy applies for the given context, satisfied determines
    #   if the actual rules of the policy are met.
    #
    # returns a Hash mapping a policy symbol to one of the following symbols representing the result of evaluating it:
    #   - :unsatisifed - The policy is not satisfied.
    #   - :satisfied - The policy was evaluated and satisfied.
    #   - :inapplicable - The policy was not applicable on the resource.
    #   - :unenforceable - The policy was not enforceable on the resource.
    #   - If a policy is not present in the result, then it was not evaluated
    #     (either because fail_fast was set and a policy preceding it was :unsatisfied,
    #      or it wasn't in the set of evaluated policies)
    def evaluate_conditional_access_policies(resource, policies: conditional_access_policies, fail_fast: false)
      results = do_evaluate_conditional_access_policies_authzd_cutover(resource, policies: policies, fail_fast: fail_fast)
      results
    end

    # Evaluates policies until the first policy fails and enforces it.
    #
    # This is a convenience method for callsites that only care about enforcement.
    # Example usage: return unless enforce_conditional_access_policies == :ok
    #
    # - resource: the object we want to enforce conditional access to. Must respond to :target_for_conditional_access.
    # - policies: allows overriding the policies to enforce
    #
    # returns :ok if all policies were met, otherwise it returns the symbol representing the name of the
    #         failed policy that was enforced
    def enforce_conditional_access_policies(resource, policies: conditional_access_policies)
      begin
        results = do_evaluate_conditional_access_policies_authzd_cutover(resource, policies: policies, fail_fast: true)

        unsatisfied_policy, _ = results.find { |_policy, result| result == :unsatisfied }
        return :ok if unsatisfied_policy.nil?

        target = target_provider.target(resource)
        raise ArgumentError.new("nil is not a valid target_for_conditional_access return value, only User/Organization/Business accepted") if target.nil?

      rescue StandardError => ex # rubocop:disable Lint/RescueException
        GitHub.logger.error({ :exception => ex, "code.namespace" => self.class.name, "service.name" => "cap" })
        raise
      ensure
        GitHub.dogstats.count("cap.enforcer.executed", 1, tags: ["success:#{ex.nil?}", "error:#{ex&.class&.name}"])
      end

      enforce(target, unsatisfied_policy)
      unsatisfied_policy
    end

    # Evaluates the provided policies, populating a cache to store results for future evaluations.
    # This method only preloads results for future authzd CAP calls.
    # Returns a boolean indicating if preloading occurred.
    def preload_policies(resource, policies)
      # preloading may be wasted if the results of these FF checks changes during a request
      # ie when checked here and then later on during do_evaluate_conditional_access_policies_authzd_cutover
      # However, both checks support actor-based enablement and anonymous requests make up a small portion of overall API requests (~3%)
      # We will enable both via actor %, starting with the experiment flag. This will allow us to verify correctness when compared to the control via the existing experiment.
      if use_authzd_cap?
        authzd_evaluate_conditional_access_policies(resource, policies: policies, fail_fast: false, serving_prod_traffic: true)
        GitHub.dogstats.count("authzd.cap.preload_policies", 1, tags: ["preloaded:true", "reason:using_authzd_cap", "location:#{location}"])
        true
      elsif run_authzd_cap_experiment?(resource)
        authzd_evaluate_conditional_access_policies(resource, policies: policies, fail_fast: false, serving_prod_traffic: false)
        GitHub.dogstats.count("authzd.cap.preload_policies", 1, tags: ["preloaded:true", "reason:authzd_cap_experiment", "location:#{location}"])
        true
      else
        GitHub.dogstats.count("authzd.cap.preload_policies", 1, tags: ["preloaded:false", "reason:not_authzd_cap", "location:#{location}"])
        false
      end
    end

    # Returns the set of policies to be enforced BY DEFAULT. Classes including this method should define the policies to enforce.
    #
    # returns returns an array of symbols that identify the policies to enforce
    def conditional_access_policies
      raise Error, "#{self.class} must implement conditional_access_policies method"
    end

    # Returns the set of policies registered but not necessarily run by default.
    #
    # returns returns an array of symbols that identify the policies
    def registered_policies
      raise Error, "#{self.class} must implement registered_policies method"
    end

    # Returns the set of policies that should be compared to their authzd implementations. This should be overridden in subclasses.
    #
    # returns an array of policy name symbols.
    def authzd_science_policies
      []
    end

    def authzd_cap_request(attrs:, target:)
      results = {}
      result_messages = {}
      result_codes = {}

      authzd_attrs = attrs.map do |k, v|
        Authzd::Proto::Attribute.wrap(k, v)
      end

      authz_request = Authzd::CapEvaluator::SingleResourceRequest.new(attributes: authzd_attrs)

      headers = {}
      headers["X-Github-Features"] = github_features_header(target) if Rails.env.test? # rubocop:disable GitHub/DoNotBranchOnRailsEnv
      headers["X-Github-Capabilities"] = github_capabilities_header if Rails.env.test? # rubocop:disable GitHub/DoNotBranchOnRailsEnv


      cap_results = tracer.in_span("Authzd.conditional_access_client.evaluate_policies_for_single_resource",
        attributes: {
          GitHub::TaggingHelper::CATALOG_SERVICE_TAG => "github/conditional_access",
          "code.function" => __method__.to_s,
          "code.namespace" => self.class.name,
          "cap.callback" => callback_name,
          "cap.location" => location.to_s,
        }, kind: :internal) do
        Authzd.conditional_access_client.evaluate_policies_for_single_resource(
          authz_request,
          headers,
        )
      end

      if cap_results.error
        raise AuthzdServerError, "Authzd CAP evaluation failed: #{cap_results.error}"
      end

      cap_results.data.results.each do |r|
        key = r.policy.to_sym

        results[key] = r.outcome.downcase
        result_messages[key] = r.enforcement_message
        result_codes[key] = r.enforcement_code&.presence&.to_sym || :UNKNOWN
      end

      [results, result_messages, result_codes]
    rescue Faraday::Error, AuthzdServerError => err
      GitHub.dogstats.increment("cap.enforcer.evaluation.authzd_request.failure", tags: ["location:#{location}", "callback:#{callback_name}"])
      wrapped_err = EnforcerError.new(err)
      Failbot.report!(wrapped_err)
      # there's no sensible way to handle an error from authzd here
      # we _could_ return a hash where all policies are unsatisfied,
      # but that would be a lie. So we reraise the error
      raise wrapped_err
    end

    # Experimental: This function should not be used for production code
    #
    # authzd_evaluate_conditional_access_policies_through_authzd is using the new implementation of CAP in Authzd
    # The policies in Authzd are ports of the existing CAP policies, but they are not 100% feature complete.
    # This function is used in a science experiment to compare the Authzd and Dotcom CAP results
    def authzd_evaluate_conditional_access_policies(resource, policies: conditional_access_policies, fail_fast: false, preresolved_target: nil, serving_prod_traffic: false, force_repository_id_attr: nil)
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      authzd_evaluate_conditional_access_policies_cached(resource, policies:, fail_fast:, preresolved_target:, serving_prod_traffic:, force_repository_id_attr:)
    rescue StandardError => ex
      raise
    ensure
      end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      tags = ["location:#{location}", "callback:#{callback_name}", "authzd:true", "success:#{ex.nil?}", "error:#{ex&.class&.name}"]

      GitHub.dogstats.distribution("cap.enforcer.evaluation.dist", (end_time - T.must(start_time)) * 1_000, tags: tags)
    end

    def authzd_evaluate_conditional_access_policies_cached(resource, policies: conditional_access_policies, fail_fast: false, preresolved_target: nil, serving_prod_traffic: false, force_repository_id_attr: nil)
      policies = policies & authzd_science_policies

      tracer.in_span("do_evaluate_conditional_access_policies_through_authzd_cached",
                            attributes: {
                              GitHub::TaggingHelper::CATALOG_SERVICE_TAG => "github/conditional_access",
                              "code.function" => __method__.to_s,
                              "code.namespace" => self.class.name,
                              "cap.callback" => callback_name,
                              "cap.cached" => false,
                              "cap.location" => location.to_s,
                              "cap.policies" => "#{policies}",
                            }, kind: :internal) do
        raise ConditionalAccess::Enforcer::ResourceError, "resource can't be nil" if resource.nil?
        results = {}
        result_messages = {}
        result_codes = {}

        enforceable_policies = []
        ActiveRecord::Base.connected_to(role: :reading) do
          policies.each do |policy|
            if enforceable(policy) == :no
              results[policy] = :unenforceable
            else
              enforceable_policies << policy
            end
          end
        end

        if enforceable_policies.any?
          if resource == :no_resource_for_conditional_access || resource == :no_target_for_conditional_access
            target = nil
          else
            target = if preresolved_target
              preresolved_target
            else
              target_provider.target(resource)
            end
          end

          attrs = resolve_request_attributes(resource, target, serving_prod_traffic, force_repository_id_attr)
          cache_key = attrs.clone

          # hash<symbol, symbol?>, hash<symbol, string>, hash<symbol, string>
          cached_results, cached_messages, cached_codes = @authzd_result_cache[cache_key]
          results.merge!(cached_results) if cached_results
          result_messages.merge!(cached_messages) if cached_messages
          result_codes.merge!(cached_codes) if cached_codes

          request_policies = []
          enforceable_policies.each do |p|
            hit = !!(cached_results&.has_key?(p))
            request_policies << p unless hit

            tags = ["policy:#{p}", "location:#{location}", "hit:#{hit}"]
            GitHub.dogstats.count("cap.enforcer.cache", 1, tags: tags)
          end

          if fail_fast && results.slice(*policies).any? { |_policy, outcome| outcome == :unsatisfied }
            return [results.slice(*policies), result_messages.slice(*policies), result_codes.slice(*policies)]
          end

          if request_policies.any?
            # these attributes only affect which policies run and do not need to be included in the cache
            attrs["conditional.access.science_policies"] = request_policies
            if fail_fast
              attrs["conditional.access.fail_fast"] = true
            end

            authzd_results, authzd_messages, authzd_codes = authzd_cap_request(attrs: attrs, target: target)
            results.merge!(authzd_results)
            result_messages.merge!(authzd_messages)
            result_codes.merge!(authzd_codes)
            @authzd_result_cache[cache_key] = [results, result_messages, result_codes]
          end
        end

        [results.slice(*policies), result_messages.slice(*policies), result_codes.slice(*policies)]
      end
    end

    def resolve_request_attributes(resource, target, serving_prod_traffic, force_repository_id_attr)
      # returns a hash with all attributes except those used in policy selection
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      attrs = authzd_cap_actor_attributes
      attrs = attrs.merge(authzd_cap_and_control_access_request_attributes(resource, target, force_repository_id_attr: force_repository_id_attr))
      attrs = attrs.merge(authzd_cap_dotcom_ci_attributes) if Rails.env.test? # rubocop:disable GitHub/DoNotBranchOnRailsEnv

      attrs["conditional.access.is_science"] = !serving_prod_traffic
      attrs
    ensure
      end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      tags = ["location:#{location}", "callback:#{callback_name}"]
      GitHub.dogstats.distribution("cap.enforcer.resolve_attributes.dist", (end_time - T.must(start_time)) * 1_000, tags: tags)
    end

    def use_forced_repository_id_attr?
      return @use_forced_repository_id_attr if defined?(@use_forced_repository_id_attr)
      @use_forced_repository_id_attr = FeatureFlag.vexi.enabled?(:use_forced_repository_id_attr, default: false)
    end

    def authzd_cap_and_control_access_request_attributes(resource, target, force_repository_id_attr: nil, verb: nil)
      attrs = authzd_cap_request_attributes
      if !force_repository_id_attr.nil? && use_forced_repository_id_attr?
        if force_repository_id_attr == 0
          # remove the "conditional.access.repository_id" attribute if we've intentionally set "force_repository_id_attr" to 0
          attrs.delete("conditional.access.repository_id")
        else
          attrs["conditional.access.repository_id"] = force_repository_id_attr
        end
      end

      if !verb.nil?
        attrs["conditional.access.action"] = verb
      end

      attrs["conditional.access.enforcer.type"] = authzd_enforcer_type

      unless attrs.key?("conditional.access.ignore_repo_network_owner")
        # default to old monolith behavior but allow filters/callsites to opt-in to inline evaluation of repo network owner
        attrs["conditional.access.ignore_repo_network_owner"] = true
      end

      if GitHub.multi_tenant_enterprise? && tenant = GitHub::CurrentTenant.get
        attrs["conditional.access.tenant.id"] = tenant.id
      end

      if resource == :no_resource_for_conditional_access || resource == :no_target_for_conditional_access
        attrs["conditional.access.resource.id"] = 0
        attrs["conditional.access.resource.type"] = resource.to_s
      else
        if target == :no_target_for_conditional_access
          attrs["conditional.access.target.id"] = 0
          attrs["conditional.access.target.type"] = target.to_s
        else
          attrs["conditional.access.target.id"] = target.id
          attrs["conditional.access.target.type"] = target.class.name
        end

        if resource.is_a?(Platform::PublicResource) || resource.is_a?(Platform::InternalResource)
          inner_resource = resource.resource
          if inner_resource
            attrs["conditional.access.resource.id"] = inner_resource.try(:id) || 0
            attrs["conditional.access.resource.type"] = inner_resource.class.name
          else
            attrs["conditional.access.resource.id"] = 0
            attrs["conditional.access.resource.type"] = :no_resource_for_conditional_access.to_s
          end
        else
          attrs["conditional.access.resource.id"] = resource.try(:id) || 0
          attrs["conditional.access.resource.type"] = resource.class.name
        end
        attrs["conditional.access.resource.visibility"] = get_authzd_resource_visibility(resource)
      end
      attrs
    end

    private

    VALID_DECISIONS = [:yes, :no].freeze
    OP_ENFORCEABLE  = "enforceable"
    OP_APPLICABLE   = "applicable"
    OP_SATISFIED    = "satisfied"

    # do_evaluate_conditional_access_policies_authzd_cutover is used to determine which implementation of
    # do_evaluate_conditional_access_policies to use (authzd, science, or dotcom)
    def do_evaluate_conditional_access_policies_authzd_cutover(resource, policies: conditional_access_policies, fail_fast: false)
      if use_authzd_cap?
        result, enforcement_messages = authzd_evaluate_conditional_access_policies(resource, policies: policies, fail_fast: fail_fast, serving_prod_traffic: true)

        # note - we're _only_ using external_conditional_access_policy messages from authzd
        # for now, since that message is sometimes built using the response message from the IdP
        # other policies, can continue constructing the enforcement message on their own for now.
        if enforcement_messages&.any? && enforcement_messages.has_key?(:external_conditional_access_policy) && enforcement_messages[:external_conditional_access_policy].present?
          @idp_message = enforcement_messages[:external_conditional_access_policy]
        end

        result
      elsif run_authzd_cap_experiment?(resource)
        do_evaluate_conditional_access_policies_with_science(resource, policies: policies, fail_fast: fail_fast)
      else
        do_evaluate_conditional_access_policies(resource, policies: policies, fail_fast: fail_fast)
      end
    end

    # the only difference with evaluate_conditional_access_policies is that it returns the target for conditional access
    # for performance reasons (avoid one redundant call).
    # If no policy is enforceable, then target will be nil as it does not need to be computed.
    # If at least one policy is enforceable, the target will be the appropriate TFCA.
    def do_evaluate_conditional_access_policies(resource, policies: conditional_access_policies, fail_fast: false)
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      results = {}
      tracer.in_span("do_evaluate_conditional_access_policies",
                            attributes: {
                              GitHub::TaggingHelper::CATALOG_SERVICE_TAG => "github/conditional_access",
                              "code.function" => __method__.to_s,
                              "code.namespace" => self.class.name,
                              "cap.callback" => callback_name,
                              "cap.cached" => false,
                              "cap.location" => location.to_s,
                              "cap.policies" => "#{policies}",
                            }, kind: :internal) do |span|
        raise ConditionalAccess::Enforcer::ResourceError, "resource can't be nil" if resource.nil?

        ActiveRecord::Base.connected_to(role: :reading) do
          policies.each do |policy|
            span.add_event("evaluating policy", attributes: { "policy" => policy.to_s })
            if enforceable(policy) == :no
              results[policy] = :unenforceable
            else
              if applicable(resource, policy) == :no
                results[policy] = :inapplicable
              elsif satisfied(resource, policy) == :yes
                results[policy] = :satisfied
              else
                results[policy] = :unsatisfied
                break if fail_fast
              end
            end
            span.add_event("policy complete", attributes: { "results" => results[policy].to_s })
          end
          next results
        end
      end
    ensure
      end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      tags = ["location:#{location}", "callback:#{callback_name}", "cached:false", "authzd:false"]
      GitHub.dogstats.distribution("cap.enforcer.evaluation.dist", (end_time - T.must(start_time)) * 1_000, tags: tags)

      unsatisfied_tags = []
      results&.each do |policy, result|
        if result == :unsatisfied
          unsatisfied_tags << "#{policy}:unsatisfied"
        end
      end
      if unsatisfied_tags.any?
        unsatisfied_tags << "location:#{location}"
        GitHub.dogstats.count("cap.enforcer.unsatisfied", 1, tags: unsatisfied_tags)
      end
    end

    def do_evaluate_conditional_access_policies_with_science(resource, policies: conditional_access_policies, fail_fast: false)
      policies_for_authzd = policies & authzd_science_policies

      # we have other metrics to track the performance of the control
      # but we aren't able to use them to only emit metrics when the candidate has
      # a corresponding metric. So we need to track the control timing here, and emit it in the
      # compare, when we know the candidate has a corresponding metric.
      control_timing = T.let(0, T.any(Integer, Float))

      experiment_name = "authzd_cap_#{location}"
      science_class = GitHub.multi_tenant_enterprise? && !Rails.env.test? ? ProximaScientist : Scientist # rubocop:disable GitHub/DoNotBranchOnRailsEnv
      science_class.run experiment_name do |e|
        e.use do
          control_start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          control_result = do_evaluate_conditional_access_policies(resource, policies: policies, fail_fast: fail_fast)
          control_end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          control_timing = (control_end_time - T.must(control_start_time)) * 1_000
          control_result
        end
        e.try do
          # Note: we are not yet using the messages from Authzd
          # returning them now only for experiment mismatch evaluation
          result, messages = authzd_evaluate_conditional_access_policies(resource, policies: policies_for_authzd, fail_fast: fail_fast)
          [result, messages]
        end
        e.compare do |control, candidate|
          original_control = control
          original_candidate = candidate
          candidate, candidate_messages = candidate
          GitHub.dogstats.distribution("cap.enforcer.experiment.control_timing", control_timing, tags: ["location:#{location}", "callback:#{callback_name}"])

          # remove the unenforceable results from the comparison - since failfast can
          # affect the results. The control checks each policy (enforceable, applicable, satisfied) in order
          # while the candidate checks all enforcability upfront. If we don't ignore them, the candidate
          # may have more policies in the result set marked as unenforceable than the control when fail fast is triggered.
          control = control.reject { |k, _v| control[k] == :unenforceable }
          candidate = candidate.reject { |k, _v| candidate[k] == :unenforceable }

          # ignore cases where we reach the 'satisfied' method in both external cap implementations,
          # and the authzd implementation performs a stubbed token refresh request
          if candidate_messages&.dig(:external_conditional_access_policy) == "No request was attempted." \
            && [:satisfied, :unsatisfied].include?(control.dig(:external_conditional_access_policy))
            control = control.reject { |k, _v| k == :external_conditional_access_policy }
            candidate = candidate.reject { |k, _v| k == :external_conditional_access_policy }
          end


          control_unsatisfied = control.any? { |_k, v| v == :unsatisfied }
          candidate_unsatisfied = candidate.any? { |_k, v| v == :unsatisfied }

          # only compare experimental policies
          control = control.select { |k, _v| policies_for_authzd.include?(k) }

          if fail_fast
            control = control.select { |k, _v| candidate.keys.include?(k) }
            candidate = candidate.select { |k, _v| control.keys.include?(k) }
          end

          matched = (control == candidate) && (control_unsatisfied == candidate_unsatisfied)

          tags = ["match:#{matched}", "enforcer:#{location}"]

          # being extra safe here by wrapping in a try catch.
          # we don't want any chance that this compare could raise an exception and affect the actual request
          begin
            if !matched
              opted_out = ConditionalAccess::AuthzdRollout.any_biz_with_enterprise_teams?(authzd_cap_actor_businesses)
              tags << "actor_opted_out_for_biz_teams:#{opted_out}"

              target = begin
                target_provider.target(resource)
              rescue StandardError => ex # rubocop:todo Lint/RescueException
                nil
              end
              actor_flipper_id = authzd_cap_actor&.try(:flipper_id)
              tfca_flipper_id = target&.try(:flipper_id)

              # This log is all we have if we're using the custom ProximaScientist class.
              # We won't have the Scientist UI tooling with all of the context about mismatches
              # The log automatically has the request ID, which can help us diagnose further if needed
              # We will also log in dotcom to include additional details like opt-out status and target info
              # which is too expensive to compute for the experiment context (context is computed on every request, even if science is disabled)
              # https://github.com/github/scientist/blob/504a396e987f655a21c6bf2ed57935aadaa40859/lib/scientist/experiment.rb#L222-L235
              GitHub.logger.info(
                "Mismatch in authzd cap experiment",
                "code.function" => "do_evaluate_conditional_access_policies_with_science",
                "authzd.cap.experiment_name" => experiment_name,
                "authzd.cap.location" => location,
                "authzd.cap.callback" => callback_name,
                "authzd.cap.policies" => "#{policies}",
                "authzd.cap.control" => "#{original_control}",
                "authzd.cap.candidate" => "#{original_candidate}",
                "authzd.cap.fail_fast" => fail_fast,
                "authzd.cap.resource.id" => resource&.try(:id) || 0,
                "authzd.cap.resource.type" => resource&.class&.name,
                "authzd.cap.target.id" => target&.try(:id) || 0,
                "authzd.cap.target.type" => target&.class&.name,
                "authzd.cap.target_flipper_id" => tfca_flipper_id,
                "authzd.cap.actor_flipper_id" => actor_flipper_id,
                "authzd.cap.participating_in_biz_teams" => opted_out,
              )
            end

            control.keys.each do |policy|
              if candidate.nil?
                tags << "#{policy}:mismatch"
                tags << "#{policy}_control:#{control[policy]}"
                tags << "#{policy}_candidate:nil"
              else
                tags << "#{policy}:#{control[policy] == candidate[policy] ? "match" : "mismatch"}"
                tags << "#{policy}_control:#{control[policy]}"
                tags << "#{policy}_candidate:#{candidate[policy]}"
              end
            end
            GitHub.dogstats.count("cap_extraction_experiment_result", 1, tags: tags)
          rescue StandardError => ex # rubocop:todo Lint/RescueException
            # we can still stat the match and enforcer tags here in the case where
            # we may have caused an exception in the block above calculating the more detailed tags
            GitHub.dogstats.count("cap_extraction_experiment_result", 1, tags: tags)
          end
          matched
        end
      end
    end

    # Returns the visibility of the resource as a string.
    #
    # This was taken from Organization::CredentialAuthorization#is_resource_internal_or_public?
    def get_authzd_resource_visibility(resource)
      case resource
      when Repository
        return get_visibility_for_repo(resource)
      when Integration
        # Taken from packages/apps/app/models/integration/visibility_dependency.rb
        return "public" if resource.public_visibility?
        return "internal" if resource.internal_visibility?
      when MemexProject
        return "public" if resource.public?
        # Note: in credential_organization, we also have resource.owner.same_business_as_org?(org) for determining internal
        # but we don't have an org here, so skipping that check for now.
        return "internal" if  resource.org_owned?
      when Project
        return get_visibility_for_repo(resource.owner)  if resource.owner_type == "Repository"
      when Platform::Models::NotificationThread
        if resource.subject.respond_to?(:repository) && resource.subject.repository.is_a?(Repository)
          return get_visibility_for_repo(resource.subject.repository)
        end
      when Platform::PublicResource
        return "public"
      when Platform::InternalResource
        return "internal"
      else
        # Check if this resource has a repository and if that repository is internal or public.
        if resource.respond_to?(:repository) && resource.repository.is_a?(Repository)
          return get_visibility_for_repo(resource.repository)
        end
      end
      "private"
    end

    def get_visibility_for_repo(repo)
      if authzd_enforcer_type == "GitAuth"
        # For private repos, if feature flag is enabled for the user associated with the credential,
        # then treat as internal repo and allow access. This is to allow repo migrations to for multiple
        # organizations work without needing an authorized PAT for each org.
        user = if a = authzd_cap_actor
          if a.is_a?(User)
            a
          else
            a.respond_to?(:user) ? a.user : nil
          end
        end
        allow_private_repo = repo.private? && !user.nil? && user.feature_flag_enabled?(:sso_same_business_cred_authz_private_repos, default: false)

        if allow_private_repo || repo.internal? || (repo.fork? && repo.private? && repo.async_root.sync.internal?)
          return "internal"
        end
      end

      repo.visibility
    end

    # Returns :yes if the provided policy is enforceable in the current context.
    # Enforceability is a means to make it possible for classes to opt-out from the enforcement.
    # Every policy is enforceable by default, unless specified otherwise explicitly.
    #
    # For example, for a SAML policy, this would allow SAML-related controllers to opt-out
    # from the enforcement altogether.
    #
    # policy - Symbol that identifies a specific policy. It must be registered
    #          in the policy registry
    #
    # returns :yes if the policy is enforceable, :no otherwise
    def enforceable(policy)
      run_operation(resource: nil, policy: policy, operation: OP_ENFORCEABLE, default_decision: :yes, forward_target_and_resource: false)
    end

    # Returns :yes if the provided policy is applicable in the current context.
    # A policy being applicable means the conditions provided by the context determine
    # the policy is elegible to be enforced.
    #
    # For example, in a SAML enforced Organization, applicable will determine if SAML
    # enforcement has been enabled for the owner of a resource.
    #
    # resource  - an object that responds to target_for_conditional
    # target_provider - the target provider for conditional access over which to compute applicability of the policy
    # policy - Symbol that identifies a specific policy. It must be registered
    #          in the policy registry
    #
    # returns :yes if the policy is applicable, :no otherwise
    def applicable(resource, policy)
      run_operation(resource: resource, policy: policy, operation: OP_APPLICABLE, default_decision: :yes, forward_target_and_resource: true)
    end

    # Returns :yes if the provided policy identifier is satisfied in the current context.
    # A policy being satisfied means that the policy rules or conditions are met within the
    # specified context.
    #
    # resource  - an object that responds to target_for_conditional
    # target - the target provider for conditional access over which the enforcer will determine
    #          if the policy was satisfied
    # policy - Symbol that identifies a specific policy. It must be registered
    #          in the policy registry
    #
    # returns :yes if the policy is satisfied, :no otherwise
    def satisfied(resource, policy)
      run_operation(resource: resource, policy: policy, operation: OP_SATISFIED, default_decision: :no, forward_target_and_resource: true)
    end

    # Performs the action needed when a policy is not met. This could be a status 4XX, a redirection,
    # or prompting the user to perform some action to satisfy the policy, like performing SSO.
    #
    # target - the target for conditional for which to enforce the policy because it wasn't met
    # policy - Symbol that identifies a specific policy. It must be registered
    #          in the policy registry
    #
    # returns nil
    def enforce(target, policy)
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      method = "#{policy}_enforce".to_sym

      tracer.in_span("#{method}",
                            attributes: {
                              GitHub::TaggingHelper::CATALOG_SERVICE_TAG => "github/conditional_access",
                              "code.function" => __method__.to_s,
                              "code.namespace" => self.class.name,
                              "cap.location" => location.to_s,
                              "cap.callback" => callback_name,
                              "cap.policy" => "#{policy}",
                              "cap.operation" => "enforce",
                            }, kind: :internal) do |span|
        raise_if_unknown_policy(policy)

        # let callback take priority in defining the enforcement operation
        if callback.respond_to?(method, true)
          span.set_attribute("cap.callbackDefinedEnforcement", true)
          callback.send(method, target)
          next
        end

        span.set_attribute("cap.callbackDefinedEnforcement", false)

        # if callback didn't define the operation, determine if this enforcer instance defined it
        raise Error, "#{method} not implemented" unless respond_to?(method, true)

        send(method, target)
        nil
      end
    ensure
      end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      tags = ["policy:#{policy}", "operation:enforce", "location:#{location}", "callback:#{callback_name}"]
      GitHub.dogstats.distribution("cap.enforcer.operation.dist", (end_time - T.must(start_time)) * 1_000, tags: tags)
    end

    def run_operation(resource:, policy:, operation:, default_decision:, forward_target_and_resource: false)
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      method = "#{policy}_#{operation}".to_sym
      begin
        raise_if_unknown_policy(policy)

        # let callback take priority in defining the operation
        if callback.respond_to?(method, true)
          # we use forward_target_and_resource to determine if a given phase of the enforcement workflow
          # needs the target for conditional access and resource as arguments
          decision = if forward_target_and_resource
            callback.send(method, resource: resource, target_provider: target_provider)
          else
            callback.send(method)
          end
          return decision if VALID_DECISIONS.include?(decision)
        end
        # if callback didn't define the operation, determine if this enforcer instance defined it
        return default_decision unless respond_to?(method, true)
        decision = if forward_target_and_resource
          send(method, resource: resource, target_provider: target_provider)
        else
          send(method)
        end

        return decision if VALID_DECISIONS.include?(decision)

        raise Error, "invalid decision returned by #{method} - should be any of #{VALID_DECISIONS}"
      rescue StandardError => ex # rubocop:todo Lint/RescueException
        GitHub.logger.error({ :exception => ex, "code.namespace" => self.class.name, "service.name" => "cap" })
        raise ex
      ensure
        end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        tags = ["policy:#{policy}", "operation:#{operation}", "location:#{location}", "callback:#{callback_name}", "decision:#{decision}"]
        GitHub.dogstats.distribution("cap.enforcer.operation.dist", (end_time - start_time) * 1_000, tags: tags)
      end
    end

    def raise_if_unknown_policy(policy)
      raise Error, "unknown policy #{policy}" unless registered_policies.include?(policy)
    end

    # returns the name of the callback
    def callback_name
      cb = callback
      return cb.name if cb.is_a?(Class)
      cb.class.name
    end

    # where is this request coming from, API, Web, GitAuth?
    def location
      raise NotImplementedError, "subclasses should implement their own location"
    end

    # what attributes should be sent to authzd?
    def authzd_cap_request_attributes
      raise Error, "#{self.class} must implement authzd_cap_request_attributes method"
    end

    # set if the Enforcer requires special behaviour of one or more policies
    def authzd_enforcer_type
      ""
    end

    def run_authzd_cap_experiment?(resource = nil)
      return false unless do_authzd_science

      if Rails.env.test? && GitHub.single_tenant_enterprise? # rubocop:disable GitHub/DoNotBranchOnRailsEnv
        return true
      end

      # run_authzd_cap_experiment will be enabled 100% or 0%
      # participation rate by location is controlled by the location flag (ex 1% of api, 10% of web)
      location_flag = "run_authzd_cap_experiment_#{location}".to_sym
      return false unless FeatureFlag.vexi.enabled?(:run_authzd_cap_experiment, default: false)

      actors = [authzd_cap_actor]
      actors << GitHub::RequestIdVexiActor.new(GitHub.context[:request_id]) if GitHub.context[:request_id].present?
      return true if FeatureFlag.vexi.enabled?(location_flag, actors, default: false)
      return true if run_authzd_cap_experiment_for_actor?
      run_authzd_cap_experiment_for_target?(resource)
    end

    def run_authzd_cap_experiment_for_actor?
      # we don't want to run the experiment all the time for selected actors, so use a second flag to tune participation rate
      return false unless authzd_cap_actor&.respond_to?(:flipper_id)
      return false unless FeatureFlag.vexi.enabled?(:authzd_cap_experiment_actor_participation_rate, default: false)
      FeatureFlag.vexi.enabled?(:run_authzd_cap_experiment_for_actor, authzd_cap_actor, default: false)
    end

    def run_authzd_cap_experiment_for_target?(resource)
      return false unless resource
      return false unless FeatureFlag.vexi.enabled?(:authzd_cap_experiment_tfca_participation_rate, default: false)
      target = begin
        target_provider.target(resource)
      rescue ArgumentError
        nil
      end
      return false unless target&.try(:flipper_id)
      FeatureFlag.vexi.enabled?(:run_authzd_cap_experiment_for_tfca, target, default: false)
    end
  end
end
