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

      # filters organizations for the multiple-satisfied check
      # for orgs the user is affiliated with directly, we can check the orgs policy directly
      # for orgs the user is affiliated with via a business, we only check the business policy
      sig { params(user: User, is_two_factor_enabled: T::Boolean, organizations: T::Array[Organization]).returns(T::Hash[Organization, T::Hash[Symbol, Symbol]]) }
      def filter_organizations_satisfied(user, is_two_factor_enabled, organizations)
        # partition the org targets into a list of orgs that the user is directly affiliated with
        # and a list of orgs that the user is indirectly affiliated with (i.e. through business membership)
        # we only want to apply the _org_ policies to the set of orgs the user is directly affiliated with
        # the indirect orgs, we'll lookup the businesses for, and apply satification checks based on the business policies only
        direct, indirect = user.filter_affiliated_organizations_direct_and_indirect(organizations)
        direct_orgs_filter_result = filter_direct_organizations_satisfied(user, is_two_factor_enabled, direct)

        # if we don't have any indirect orgs, we can stop here and return the results
        return direct_orgs_filter_result if indirect.empty?

        org_lookup = T.let(indirect.index_by(&:id), T::Hash[Integer, Organization])

        # get all the business relations for the indirect orgs that have a business
        business_memberships = Business::OrganizationMembership
          .where(organization_id: indirect)
          .includes(:business)
        businesses = T.let({}, T::Hash[Integer, Business])

        # get a list of those unique businesses, and build a mapping back to the corresponding orgs
        business_to_orgs_mapping = T.let({}, T::Hash[Integer, T::Array[Organization]])
        business_memberships.each do |bm|
          if bm.business
            businesses[bm.business.id] = bm.business
            business_to_orgs_mapping[bm.business.id] ||= []
            T.must(business_to_orgs_mapping[bm.business.id]) << T.must(org_lookup[bm.organization_id])
          end
        end

        # from the businesses filter result, reconstruct the orgs filter result by looking up the orgs for each business
        businesses_filter_result = filter_businesses_satisfied(user, is_two_factor_enabled, businesses.values)
        indirect_orgs_filter_result = T.let(Hash.new { |h, k| h[k] = {} }, T::Hash[Organization, T::Hash[Symbol, Symbol]])
        businesses_filter_result.each do |business, result|
          orgs = business_to_orgs_mapping[business.id]
          orgs&.each do |o|
            indirect_orgs_filter_result[o] = result
          end
        end

        # return the results of the direct orgs filter and the indirect orgs filter
        direct_orgs_filter_result.merge(indirect_orgs_filter_result)
      end

      # filters organizations for the multiple-satisfied check only for orgs the user is directly affiliated with
      sig { params(user: User, is_two_factor_enabled: T::Boolean, organizations: T::Array[Organization]).returns(T::Hash[Organization, T::Hash[Symbol, Symbol]]) }
      def filter_direct_organizations_satisfied(user, is_two_factor_enabled, organizations)
        result = Hash.new { |h, k| h[k] = {} }
        orgs_with_disallowed_methods = orgs_with_disallowed_methods(organizations)
        organizations.each do |target|
          if is_two_factor_enabled
            # orgs that definitely have disallowed methods set
            if orgs_with_disallowed_methods.keys.include?(target)
              known_disallowed_methods = orgs_with_disallowed_methods[target]
              result[target] = {
                private: !user.disallowed_methods_configured(target, known_disallowed_methods: known_disallowed_methods).any? ? :satisfied : :unsatisfied,
              }
            # if no disallowed methods, then any 2FA is fine
            else
              result[target] = {
                private: :satisfied,
              }
            end
          # no 2FA at all
          else
            result[target] = {
              private: :unsatisfied,
            }
          end
        end
        result
      end

      # filters businesses for the multiple-satisfied check
      sig { params(user: User, is_two_factor_enabled: T::Boolean, businesses: T::Array[Business]).returns(T::Hash[Business, T::Hash[Symbol, Symbol]]) }
      def filter_businesses_satisfied(user, is_two_factor_enabled, businesses)
        result = Hash.new { |h, k| h[k] = {} }
        businesses_with_disallowed_methods = businesses_with_disallowed_methods(businesses)
        businesses.each do |target|
          if is_two_factor_enabled
            # businesses that definitely have disallowed methods set
            if businesses_with_disallowed_methods.keys.include?(target)
              known_disallowed_methods = businesses_with_disallowed_methods[target]
              result[target] = {
                private: !user.disallowed_methods_configured(target, known_disallowed_methods: known_disallowed_methods).any? ? :satisfied : :unsatisfied,
              }
            # if no disallowed methods, then any 2FA is fine
            else
              result[target] = {
                private: :satisfied,
              }
            end
          # no 2FA at all
          else
            result[target] = {
              "private": :unsatisfied,
            }
          end
        end
        result
      end

      # computes satisfiability of this policy over N targets for conditional access
      #
      # targets - an Enumerable of targets for conditional access
      #
      # Returns Array[targets] that for which this policy is applicable
      sig { params(targets: T::Array[T.untyped], target_provider: T.untyped).returns(T::Hash[T.any(Business, Organization), T::Hash[Symbol, Symbol]]) }
      def multiple_two_factor_satisfied_new(targets, target_provider)
        return Hash.new { |h, k| h[k] = {} } if targets.empty?

        user = T.unsafe(self).actor
        return Hash.new { |h, k| h[k] = {} } unless user.instance_of?(User)
        is_two_factor_enabled = user.two_factor_authentication_enabled?

        target_type = targets.first.class
        if target_type == Business
          return filter_businesses_satisfied(user, is_two_factor_enabled, targets)
        elsif target_type == Organization
          return filter_organizations_satisfied(user, is_two_factor_enabled, targets)
        end

        result = Hash.new { |h, k| h[k] = {} }
        targets.each do |target|
          result[target] =
          {
            # two factor satisfied for private
            "private": is_two_factor_enabled ? :satisfied : :unsatisfied,
          }
        end
        result
      end

      def multiple_two_factor_satisfied(targets, target_provider)
        multiple_two_factor_satisfied_new(targets, target_provider)
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

          # 2FA requirement enabled
          return :no unless target.two_factor_requirement_enabled?

          user = get_actor
          if target_is_org
            GitHub.tracer.in_span("user.affiliated_with_organization") do |_span|
              if !user.affiliated_with_organization?(target, include_collaboration: false)
                return :no unless target.business&.id
                return :no if !user.cap_enforcement_is_business_member?(target.business&.id)
              end
            end
          end
          GitHub.tracer.in_span("user.cap_enforcement_is_business_member") do |_span|
            return :no if target_is_business && !user.cap_enforcement_is_business_member?(target.id)
          end
          :yes
        end
      end

      # The 2FA policy is satisfied when the user has 2FA enabled
      def two_factor_satisfied(resource:, target_provider:)
        user = get_actor
        return :yes unless user.instance_of?(User)

        is_two_factor_enabled = user.two_factor_authentication_enabled?

        target = target_provider.target(resource)
        target_is_org = target.is_a?(Organization)
        target_is_business = target.is_a?(Business)

        # if the target is an org, and the user is not directly affiliated with the org,
        # we should only check the org's business for 2FA requirement
        due_to_bugfix = false
        if target_is_org && !user.affiliated_with_organization?(target, include_collaboration: false)
          biz = target.business
          return :yes unless biz
          target = biz
          target_is_org = false
          target_is_business = true
          due_to_bugfix = true
        end

        business_id = target_is_org ? target.business&.id : target&.id
        if target_is_org || target_is_business
          unless is_two_factor_enabled
            return :no
          end
          if target == :no_target_for_conditional_access
            return :no
          end
          if user.has_any_given_2fa_methods_configured?(target.get_two_factor_disallowed_methods)
            return :no
          end
          :yes
        else
          return :yes if is_two_factor_enabled
          :no
        end
      end

      private

      def get_actor
        T.unsafe(self).respond_to?(:true_actor) ? T.unsafe(self).true_actor : T.unsafe(self).actor
      end

      memoize def policy_prereqs_met?
        GitHub.tracer.in_span("policy_prereqs_met") do
          # 2FA requirement cannot be enabled in multi tenant enterprise
          return false if GitHub.multi_tenant_enterprise?
          return false if T.unsafe(self).anonymous?
          user = get_actor
          return false unless user.instance_of?(User)
          return false if user.site_admin?
          # EMU users cannot enable 2FA
          return false if user.is_enterprise_managed?
          return false unless GitHub.auth.two_factor_authentication_allowed?(user)
          true
        end
      end

      # if the targets are organizations, we need to perform lookups against the organization _and_ the corresponding business (if it exists),
      # but we can eliminate N+1's by using the business_id and running bulk queries
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

          direct, indirect = user.filter_affiliated_organizations_direct_and_indirect(filtered)
          direct.union(indirect)
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
