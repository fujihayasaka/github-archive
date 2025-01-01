# typed: false
# frozen_string_literal: true

class ConditionalAccess::TargetProvider
  attr_accessor :location, :callback_name

  def initialize(location:, callback_name:)
    @location = location
    @callback_name = callback_name
    @resource_target_cache = {}
  end

  def target(resource)
    cached_target = @resource_target_cache[resource]
    return cached_target unless cached_target.nil?

    @resource_target_cache[resource] = safe_target_for_conditional_access(resource)
  end

  private

  # safe_target_for_conditional_access is the gatekeeper to compute the target for conditional access.
  # This method makes sure that target_for_conditional_access methods complies with the contract.
  #
  # - resource: the object we want to enforce conditional access to. Must respond to :target_for_conditional_access.
  #             For example, if a Repository is the resource, its TFCA is the owning User/Organization
  #
  # The contract is:
  # - return the owner of the resource, so long it's one of the accepted types [User, Organization, Business]
  # - indicate the circumstances in which there is no target for enforcement by returning :no_target_for_conditional_access
  #
  # this method should never be overridden by includers
  def safe_target_for_conditional_access(resource)
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    return :no_target_for_conditional_access if resource == :no_resource_for_conditional_access
    return :no_target_for_conditional_access if resource == :no_target_for_conditional_access

    # performance optimization (avoids superfluous send(:target_for_conditional_access))
    return resource if resource.instance_of?(User) || resource.instance_of?(Organization) || resource.instance_of?(Business)

    raise ArgumentError, "nil is not a valid resource value in safe_target_for_conditional_access" if resource.nil?
    # workarounds a weird phenomenon: couldn't call target_for_conditional_access directly, even if resource was "self"
    local_target = resource.send(:target_for_conditional_access)
    if local_target.nil?
      resource_id = resource.try(:id) || "unknown"
      raise ArgumentError, "resource #{resource.class.name}#(id: #{resource_id}) returned nil as target_for_conditional_access"
    end

    return local_target if local_target == :no_target_for_conditional_access
    return local_target if local_target.instance_of?(User) || local_target.instance_of?(Organization) || local_target.instance_of?(Business)
    return :no_target_for_conditional_access if local_target.is_a?(User) && (local_target.bot? || local_target.mannequin?)

    raise ArgumentError, "unexpected type #{local_target.class.name} returned by target_for_conditional_access"
  ensure
    end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    tags = ["location:#{location}", "callback:#{callback_name}", "resource:#{resource&.class&.name}"]
    GitHub.dogstats.distribution("cap.target_for_conditional_access.dist", (end_time - start_time) * 1_000, tags: tags)
  end
end
