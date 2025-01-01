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
    # Outcomes that are considered "authorized" (i.e. the user should be able to access the resource)
    AUTHORIZED_OUTCOMES = [:satisfied, :inapplicable, :unenforceable]

    # All outcomes
    OUTCOMES = AUTHORIZED_OUTCOMES + [:unsatisfied]

    InvalidPolicyOutcomeError = Class.new(StandardError)

    attr_reader :callback, :target_provider

    # callback is used so that policies can perform context specific operations the enforcer cannot do itself,
    # i.e. retrieving user from the controller request, session, rendering of templates...
    def initialize(callback)
      @callback = callback
      @target_provider = TargetProvider.new(location: location, callback_name: callback_name)
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
      results  = do_evaluate_conditional_access_policies(resource, policies: policies, fail_fast: fail_fast)
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
        results = do_evaluate_conditional_access_policies(resource, policies: policies, fail_fast: true)

        unsatisfied_policy, _ = results.find { |_policy, result| result == :unsatisfied }
        return :ok if unsatisfied_policy.nil?

        target = target_provider.target(resource)
        raise ArgumentError.new("nil is not a valid target_for_conditional_access return value, only User/Organization/Business accepted") if target.nil?

      rescue StandardError => ex # rubocop:disable Lint/GenericRescue
        GitHub.logger.error({ :exception => ex, "code.namespace" => self.class.name, "service.name" => "cap" })
        raise
      ensure
        GitHub.dogstats.count("cap.enforcer.executed", 1, tags: ["success:#{ex.nil?}", "error:#{ex&.class&.name}"])
      end

      enforce(target, unsatisfied_policy)
      unsatisfied_policy
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

    private

    VALID_DECISIONS = [:yes, :no].freeze
    OP_ENFORCEABLE  = "enforceable"
    OP_APPLICABLE   = "applicable"
    OP_SATISFIED    = "satisfied"

    # the only difference with evaluate_conditional_access_policies is that it returns the target for conditional access
    # for performance reasons (avoid one redundant call).
    # If no policy is enforceable, then target will be nil as it does not need to be computed.
    # If at least one policy is enforceable, the target will be the appropriate TFCA.
    def do_evaluate_conditional_access_policies(resource, policies: conditional_access_policies, fail_fast: false)
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

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
        results = {}

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
      tags = ["location:#{location}", "callback:#{callback_name}", "cached:false"]
      GitHub.dogstats.distribution("cap.enforcer.evaluation.dist", (end_time - T.must(start_time)) * 1_000, tags: tags)
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
      rescue StandardError => ex # rubocop:todo Lint/GenericRescue
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
  end
end
