# typed: true
# frozen_string_literal: true

# A ResultSet represents a set of policy results returned by ConditionalAccess::Filter#evaluate
#
# You can access the resources themselves by calling 'resources'
# Results can also be filtered based on which policies succeeded or failed,
# as well as filtered to only resources that passed all policies, or failed any policy.
class ConditionalAccess::ResultSet
  extend Forwardable

  NotFilteredError = Class.new(StandardError)

  attr_reader :results
  def_delegators :results,
    :empty?,
    :count,
    :size,
    :any?

  # Construct a ResultSet from an Array of ConditionalAccess::Result objects.
  #
  # results: an Array of Result objects.
  def initialize(results)
    @results = results || []
    @filtered = false
  end

  # Returns all the resources contained in this ResultSet.
  # Unless the ResultSet has been filtered using #unauthorized or #authorized this will represent all resources that were evaluated!
  def resources
    @resources ||= results.map { |r| r.resource }
  end

  # Returns an Array of ids of resources contained in this ResultSet.
  # Unless the ResultSet has been filtered using #unauthorized or #authorized this will represent all resources that were evaluated!
  #
  # Raises if the underlying resource set does not respond to 'pluck' or if the underlying resource object does not respond to 'id'
  def resource_ids
    resources.pluck(:id)
  end

  # Returns the ConditionalAccess::Result for a specific resource
  def [](resource)
    results.find { |r| r.resource == resource }
  end

  # Returns a hash of 'policy => [list of unauthorized resources]',
  # where an 'unauthorized resource' is a resource for which 'policy' returned :unsatisfied.
  #
  # If a resource failed multiple policies, it will be present in the lists for all of the policies it failed.
  def by_policy
    raise NotFilteredError, "by_policy can only be called after the ResultSet has been filtered using #unauthorized or #authorized" unless @filtered

    results.each_with_object(Hash::new { |_hash, _key| [] }) do |result, by_policy|
      result.policies.each do |policy, _|
        by_policy[policy] <<= result.resource
      end
    end
  end

  # authorized returns a new ResultSet filtered to only the resources for which the provided policies were not evaluated as unsatisfied.
  # If no policies are provided via `only` argument, it returns all resources for which none of the registered policies were evaluated as unsatisfied.
  # Only resources for which a policy was deemed :unsatisfied will be excluded from these results.
  # If a policy was deemed :unenforceable, :inapplicable or :satisfied for a resource it WILL be considered authorized and be part of the returned ResultSet.
  #
  # - only: if specified, only the provided policies will be checked.
  #         Results for any other policies will be removed from the returned ResultSet
  def authorized(only: [])
    raise ArgumentError, "only cannot be nil" if only.nil?
    only = Array(only)

    new_results =
      if only.blank?
        @results.filter { |r| r.policies.all? { |_, o| ConditionalAccess::Enforcer::AUTHORIZED_OUTCOMES.include? o } }
      else
        @results.filter_map do |r|
          # Filter down to only the policies requested
          new_policies = r.policies.filter { |p, _| only.include?(p) }

          # If any of those resources have non-authorized outcomes,
          # the resource is unauthorized and should not be returned.
          next if new_policies.any? { |_, o| !ConditionalAccess::Enforcer::AUTHORIZED_OUTCOMES.include?(o) }
          ConditionalAccess::Result::new(r.resource, new_policies)
        end
      end

    result_set = ConditionalAccess::ResultSet::new(new_results)
    result_set.filtered = true
    result_set
  end

  # unauthorized returns a new ResultSet filtered to only the resources for which the provided policies were evaluated as unsatisfied.
  # If no policies are provided, it returns all resources for which any policies were evaluated as unsatisfied
  # Only resources for which a policy was deemed :unsatisfied will be included in these results.
  # If a policy was deemed :unenforceable, :inapplicable or :satisfied for a resource, then it will not be considered unauthorized and will not be present in the returned ResultSet.
  #
  # - only: if specified, only the provided policies will be checked.
  #         Results for any other policies will be removed from the returned ResultSet.
  def unauthorized(only: [])
    raise ArgumentError, "only cannot be nil" if only.nil?
    only = Array(only)

    new_results =
      if only.blank?
        @results.filter_map do |r|
          # Strip out any policy results that are considered authorized
          new_policies = r.policies.filter { |_, o| o == :unsatisfied }

          # If there are no more (unauthorized) policies remaining,
          # the resource is authorized and should not be returned
          next if new_policies.empty?
          ConditionalAccess::Result::new(r.resource, new_policies)
        end
      else
        @results.filter_map do |r|
          # Filter down to only the policies provided in 'only' and
          # strip any of those results that are considered authorized
          new_policies = r.policies.filter { |p, o| only.include?(p) && o == :unsatisfied }

          # If there are no more (unauthorized) policies remaining,
          # the resource is authorized and should not be returned
          next if new_policies.empty?
          ConditionalAccess::Result::new(r.resource, new_policies)
        end
      end

    result_set = ConditionalAccess::ResultSet::new(new_results)
    result_set.filtered = true
    result_set
  end

  def inspect
    result_strings = @results.map do |r|
      resource_str =
        if r.resource.respond_to?(:id)
          "#{r.resource.id}"
        else
          r.resource.to_s
        end
      "#{resource_str} => #{r.policies}"
    end

    "#{self.class.name}[#{result_strings.join(",")}]"
  end

  def ==(other)
    results == other.results
  end

  protected

  def filtered=(value)
    @filtered = value
  end
end
