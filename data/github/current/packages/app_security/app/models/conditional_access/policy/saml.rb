# typed: false
# frozen_string_literal: true

# Defines context agnostic logic for the SAML CAP Policy
#
# This implementation is a temporal backfill to make filtering possible with SAML in
# the CAP framework. It should eventually be redesigned to be efficient.
#
# SAML logic hasn't been migrated fully to Conditional Access Policy Framework
# and particular implementation is only being used by ConditionalAccess::Filter
module ConditionalAccess::Policy::SAML

  # computes applicability of this policy over N targets for conditional access.
  #
  # targets - an Enumerable of targets for conditional access,
  #           all resources provided MUST be of the same type.
  #
  # Returns Array[targets] that for which this policy is applicable.
  # The order of targets in the returned array is NOT guaranteed to match the input order.
  def multiple_saml_applicable(targets, target_provider)
    return [] if targets.empty?
    return [] if anonymous?

    target_type = targets.first.class
    if target_type == Organization
      Organization::SamlEnforcementPolicy.filter_enforced(targets, actor)
    elsif target_type == Business
      Business::SamlEnforcementPolicy.filter_enforced(targets, actor)
    else
      targets.filter { |t| saml_applicable(resource: t, target_provider: target_provider) == :yes }
    end
  end

  # computes satisfiability of this policy over N targets for conditional access
  #
  # targets - an Enumerable of targets for conditional access
  #
  # Returns Array[targets] that for which this policy is applicable
  def multiple_saml_satisfied(targets, target_provider)
    targets.filter { |target| saml_satisfied(resource: target, target_provider: target_provider) == :yes }
  end

  def saml_applicable(resource:, target_provider:)
    return :no if anonymous?

    target = target_provider.target(resource)
    return :no if target == :no_target_for_conditional_access

    if target.instance_of?(Organization)
      return :no unless Organization::SamlEnforcementPolicy.new(organization: target, user: actor).enforced?
    elsif target.instance_of?(Business)
      return :no unless Business::SamlEnforcementPolicy::new(business: target, user: actor).enforced?
    elsif target.instance_of?(User)
      return :no
    else
      raise ArgumentError.new("SAML Policy: unsupported target for conditional access #{target.class.name}")
    end

    :yes
  end

  def saml_satisfied(resource:, target_provider:)
    target = target_provider.target(resource)
    if target.is_a?(Organization)
      @authorized_saml_org_ids ||= authorized_saml_org_ids
      return :yes if @authorized_saml_org_ids.include?(target.id)
    elsif target.is_a?(Business)
      @authorized_saml_businesses ||= authorized_saml_businesses
      return :yes if @authorized_saml_businesses.include?(target)
    else
      raise ArgumentError.new("unsupported target for conditional access")
    end
    :no
  end

  private

  def authorized_saml_org_ids
    platform_authorization.authorized_organization_ids
  end

  def authorized_saml_businesses
    platform_authorization.authorized_businesses
  end

  def platform_authorization
    if web_session.present?
      Platform::Authorization::SAML.new(session: web_session, consider_non_enforceable_targets: true,
                                        consider_biz_only_membership: true)
    else
      Platform::Authorization::SAML.new(user: actor, consider_non_enforceable_targets: true,
                                        consider_biz_only_membership: true)
    end
  end
end
