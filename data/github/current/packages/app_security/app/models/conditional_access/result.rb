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
class ConditionalAccess::Result
  attr_reader :resource, :policies

  def initialize(resource, policies)
    raise ArgumentError, "resource cannot be nil" if resource.nil?
    raise ArgumentError, "the policies hash cannot be empty" if policies.blank?

    @resource = resource
    @policies = policies
  end

  def ==(other)
    resource == other.resource &&
      policies == other.policies
  end

  # Create convenience methods for each of the expected outcomes
  ConditionalAccess::Enforcer::OUTCOMES.each do |expected_outcome|
    define_method("#{expected_outcome}") do
      policies.filter { |_, outcome| outcome == expected_outcome }.keys
    end
  end

  # Returns a list of policies that were one of :satisfied, :inapplicable or :unenforceable
  def authorized
    policies.filter { |_, outcome| outcome == :satisfied || outcome == :inapplicable || outcome == :unenforceable }.keys
  end
end
