# typed: false
# frozen_string_literal: true

# A Result represents the result of evaluating a single resource against Conditional Access Policies
#
# #resource returns the original resource that was evaluated
#
# #policies returns a Hash mapping a policy symbol to one of the following symbols representing the result of evaluating it:
#   - :unsatisifed - The policy is not satisfied
#   - :satisfied - The policy was evaluated and satisfied
#   - If a policy is not present, then it was not evaluated (either because fail_fast was set, it wasn't in the set of evaluated policies, or it was inapplicable/unenforceable)
# #safe_request_method - if true, will allow to use a different visibility than private to determine authorization state
class ConditionalAccess::Result
  attr_reader :resource, :policies, :visibility
  DEFAULT_VISIBILITY = :private

  def initialize(resource, policies, safe_request_method: false)
    raise ArgumentError, "resource cannot be nil" if resource.nil?
    raise ArgumentError, "the policies hash cannot be empty" if policies.blank?

    @resource = resource
    @policies = policies
    # TODO not all models have a visibility method, so we need to check if it exists
    # and add that method to those models
    @visibility = (resource.respond_to?(:visibility) && safe_request_method) ? resource.visibility : DEFAULT_VISIBILITY
  end

  def ==(other)
    resource == other.resource &&
      policies == other.policies
  end

  # Create convenience methods for each of the expected outcomes
  ConditionalAccess::Enforcer::OUTCOMES.each do |expected_outcome|
    define_method("#{expected_outcome}") do
      policies.filter do |_, outcome|
        status = if outcome.is_a?(Hash)
          outcome.key?(visibility) ? outcome[visibility] : outcome[DEFAULT_VISIBILITY]
        elsif outcome.is_a?(Symbol)
          outcome
        end
        status == expected_outcome
      end.keys
    end
  end

  # Returns a list of policies that were one of :satisfied, :inapplicable or :unenforceable
  def authorized(only: [])
    policies.filter do |p, outcome|
      next if !only.empty? && !only.include?(p)

      status = if outcome.is_a?(Hash)
        outcome.key?(visibility) ? outcome[visibility] : outcome[DEFAULT_VISIBILITY]
      elsif outcome.is_a?(Symbol)
        outcome
      end
      ConditionalAccess::Enforcer::AUTHORIZED_OUTCOMES.include?(status)
    end
  end

  # Returns a boolean stating if the resource is authorized for the provided policies
  # only used by experimental functions
  def authorized?
    authorized.keys == policies.keys
  rescue NoMethodError
    # This is not expected to happen
    # Log the unexpected type of authorized
    GitHub.dogstats.count("cap.filter.result.authorized.error", 1, tags: ["authorized:#{authorized.class.name}"])
    if authorized.is_a?(Array)
      authorized == policies.keys
    else
      false
    end
  end

  # Returns a boolean stating if the resource is :satisfied for the provided policies
  def satisfied?
    policies.all? do |_, outcome|
      status = if outcome.is_a?(Hash)
        outcome.key?(visibility) ? outcome[visibility] : outcome[DEFAULT_VISIBILITY]
      elsif outcome.is_a?(Symbol)
        outcome
      end
      status == :satisfied
    end
  end

  # Returns a list of policies that were :unauthorized
  def unauthorized(only: [])
    policies.filter do |p, outcome|
      next if !only.empty? && !only.include?(p)

      status = if outcome.is_a?(Hash)
        outcome.key?(visibility) ? outcome[visibility] : outcome[DEFAULT_VISIBILITY]
      elsif outcome.is_a?(Symbol)
        outcome
      end
      status == :unsatisfied
    end
  end
end
