# typed: true
# frozen_string_literal: true

module ConditionalAccess
  module Policy
    module TwoFactorAuthn
      include GitHub::Memoizer

      # computes applicability of this policy over N targets for conditional access.
      #
      # targets - an Enumerable of targets for conditional access,
      #           all resources provided MUST be of the same type.
      #
      # Returns Array[targets] that for which this policy is applicable
      def multiple_two_factor_applicable(targets, target_provider)
        return [] unless policy_prereqs_met?
        return [] if targets.empty?

        target_type = targets.first.class
        if target_type == Organization
          filter_organizations_two_factor_applicable(targets, T.unsafe(self).actor)
        elsif target_type == Business
          filter_businesses_two_factor_applicable(targets, T.unsafe(self).actor)
        else
          # if the target isn't an org or business, we know the policy isn't applicable
          []
        end
      end

      # computes satisfiability of this policy over N targets for conditional access
      #
      # targets - an Enumerable of targets for conditional access
      #
      # Returns Array[targets] that for which this policy is applicable
      def multiple_two_factor_satisfied(targets, target_provider)
        result = Hash.new { |h, k| h[k] = {} }
        return result if targets.empty?

        user = T.unsafe(self).actor
        return result unless user.instance_of?(User)

        is_two_factor_enabled = user.two_factor_authentication_enabled?
        # results use disallowed_methods_configured over has_any_given_2fa_methods_configured? for perf, since with disallowed_methods_configured
        # we can use memoized two_factor_methods_configured and avoid repetitive db calls for what configurations the user has

        target_type = targets.first.class
        if target_type == Organization
          disallow_two_factor_methods_orgs, non_disallow_two_factor_methods_orgs = targets.partition { |t| t.enforce_two_factor_methods_policy? }
          non_disallow_two_factor_methods_orgs.each do |target|
            result[target] = {
              # two factor satisfied for private
              "private": is_two_factor_enabled ? :satisfied : :unsatisfied,
            }
          end
          orgs_with_disallowed_methods = orgs_with_disallowed_methods(disallow_two_factor_methods_orgs)
          disallow_two_factor_methods_orgs.each do |target|
            if is_two_factor_enabled
              # orgs that definitely have disallowed methods set
              if orgs_with_disallowed_methods.keys.include?(target)
                known_disallowed_methods = orgs_with_disallowed_methods[target]
                result[target] = {
                  "private": !user.disallowed_methods_configured(target, known_disallowed_methods: known_disallowed_methods).any? ? :satisfied : :unsatisfied,
                }
              # if no disallowed methods, then any 2FA is fine
              else
                result[target] = {
                  "private": :satisfied,
                }
              end
            # no 2FA at all
            else
              result[target] = {
                "private": :unsatisfied,
              }
            end
          end
        elsif target_type == Business
          # split by businesses that _may_ have some disallowed methods set
          disallow_two_factor_methods_businesses, non_disallow_two_factor_methods_businesses = targets.partition { |t| t.enforce_two_factor_methods_policy? }
          non_disallow_two_factor_methods_businesses.each do |target|
            result[target] = {
              # two factor satisfied for private
              "private": is_two_factor_enabled ? :satisfied : :unsatisfied,
            }
          end
          businesses_with_disallowed_methods = businesses_with_disallowed_methods(disallow_two_factor_methods_businesses)
          disallow_two_factor_methods_businesses.each do |target|
            if is_two_factor_enabled
              # busineses that definitely have disallowed methods set
              if businesses_with_disallowed_methods.keys.include?(target)
                known_disallowed_methods = businesses_with_disallowed_methods[target]
                result[target] = {
                  "private": !user.disallowed_methods_configured(target, known_disallowed_methods: known_disallowed_methods).any? ? :satisfied : :unsatisfied,
                }
              # if no disallowed methods, then any 2FA is fine
              else
                result[target] = {
                  "private": :satisfied,
                }
              end
            # no 2FA at all
            else
              result[target] = {
                "private": :unsatisfied,
              }
            end
          end
        else
          targets.each do |target|
            result[target] =
            {
              # two factor satisfied for private
              "private": is_two_factor_enabled ? :satisfied : :unsatisfied,
            }
          end
        end
        result
      end

      # The 2FA policy is applicable if an organization or business has the corresponding
      # option enabled
      def two_factor_applicable(resource:, target_provider:)
        GitHub.tracer.in_span("ConditionalAccess::Policy::TwoFactorAuthn#two_factor_applicable") do |_span|
          return :no unless policy_prereqs_met?

          target = GitHub.tracer.in_span("target_provider#target") do |_span|
            target_provider.target(resource)
          end
          return :no if target == :no_target_for_conditional_access

          target_is_org = target.is_a?(Organization)
          target_is_business = target.is_a?(Business)

          return :no unless target_is_org || target_is_business

          # enforcement feature flag enabled
          return :no unless target.two_factor_cap_enforcement_enabled?

          # 2FA requirement enabled
          return :no unless target.two_factor_requirement_enabled?

          user = T.unsafe(self).actor
          GitHub.tracer.in_span("user.affiliated_with_organization") do |_span|
            return :no if target_is_org && !user.affiliated_with_organization?(target, include_collaboration: false)
          end
          GitHub.tracer.in_span("user.is_business_member") do |_span|
            return :no if target_is_business && !user.is_business_member?(target.id)
          end
          :yes
        end
      end

      # The 2FA policy is satisfied when the user has 2FA enabled
      def two_factor_satisfied(resource:, target_provider:)
        user = T.unsafe(self).actor
        return :yes unless user.instance_of?(User)

        is_two_factor_enabled = user.two_factor_authentication_enabled?

        target = target_provider.target(resource)
        target_is_org = target.is_a?(Organization)
        target_is_business = target.is_a?(Business)

        if (target_is_org || target_is_business) && target.enforce_two_factor_methods_policy?
          return :no unless is_two_factor_enabled
          return :no if target == :no_target_for_conditional_access
          return :no if user.has_any_given_2fa_methods_configured?(target.get_two_factor_disallowed_methods)
          :yes
        else
          return :yes if is_two_factor_enabled
          :no
        end
      end

      private

      memoize def policy_prereqs_met?
        GitHub.tracer.in_span("policy_prereqs_met") do
          return false unless GitHub.flipper[:cap_2fa_policy_enabled].enabled?
          return false if T.unsafe(self).anonymous?
          user = T.unsafe(self).actor
          return false unless user.instance_of?(User)
          return false if user.site_admin?
          return false unless GitHub.auth.two_factor_authentication_allowed?(user)

          true
        end
      end

      # if the targets are organizations, we need to perform lookups against the organization _and_ the corresponding business (if it exists),
      # but we can eliminate N+1's by using the business_id and running bulk queries
      # note - the only thing we _cant_ skip is the :two_factor_cap_enforcement FF check for the org's business FF, since we need to pull the entire business object
      #        however, this can be removed after we get this thing rolled out
      # we perform the following steps:
      #
      # 1. check the feature flag is enabled (needs to be done once per target, and again for the organization's business if it exists)
      # 2. check the two factor requirement is enabled (accomplished via only 3 total queries, 1 for the biz memberships and 2 queries to the configuration entries table)
      # 3. check the user is affiliated with the organization (accomplished via only 2 queries see bulk_filter_affiliated)
      def filter_organizations_two_factor_applicable(organizations, user)
        GitHub.tracer.in_span("filter_organizations_two_factor_applicable") do
          return [] if organizations.empty?
          filtered = Configurable::TwoFactorRequired.filter_organizations_with_two_factor_requirement_enabled(organizations)
          return [] if filtered.empty?
          user.filter_affiliated_organizations(filtered)
        end
      end

      # if the targets are businesses, we only need to perform lookups against the business
      # we perform the following steps:
      #
      # 1. check the feature flag is enabled (needs to be done once per target)
      # 2. check the two factor requirement is enabled (accomplished via only 1 query to the configuration entries table)
      # 3. check the user is a member of the business (accomplished by querying the user's business_ids and intersecting with the remaining, filtered down targets)
      def filter_businesses_two_factor_applicable(businesses, user)
        GitHub.tracer.in_span("filter_businesses_two_factor_applicable") do
          return [] if businesses.empty?
          filtered = Configurable::TwoFactorRequired.filter_businesses_with_two_factor_requirement_enabled(businesses)
          user_business_ids_lookup = user.business_ids.index_by(&:itself)
          filtered.filter { |b| user_business_ids_lookup.key?(b.id) }
        end
      end

      sig { params(businesses: T::Array[Business]).returns(T::Hash[Business, T::Set[Symbol]]) }
      def businesses_with_disallowed_methods(businesses)
        GitHub.tracer.in_span("filter_businesses_two_factor_satisfied") do
          return Hash.new if businesses.empty?

          Configurable::TwoFactorDisallowedMethods.filter_businesses_with_two_factor_disallowed_methods(businesses)
        end
      end

      sig { params(organizations: T::Array[Organization]).returns(T::Hash[Organization, T::Set[Symbol]]) }
      def orgs_with_disallowed_methods(organizations)
        GitHub.tracer.in_span("filter_organizations_two_factor_satisfied") do
          return Hash.new if organizations.empty?

          Configurable::TwoFactorDisallowedMethods.filter_organizations_with_two_factor_disallowed_methods(organizations)
        end
      end
    end
  end
end
