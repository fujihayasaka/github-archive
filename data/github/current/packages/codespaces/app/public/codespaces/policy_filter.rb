# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Codespaces
  module PolicyFilter
    extend T::Helpers

    abstract!

    # Note that billable_owner in these methods refers to a real or hypothetical codespace's billable_owner
    # association, rather than the more general term. So it should always be a User or Organization.

    sig { abstract.returns(String) }
    def policy_name; end

    def get_allowlists(billable_owner:, repository:)
      return [] unless Codespaces::OrgPolicy.owning_organization(repository) == billable_owner

      get_constraint_values_for_policy_group_memberships(
        billable_owner:,
        repository:,
        field: :allowed_values
      )
    end

    sig { params(billable_owner: T.nilable(User), repository: T.nilable(Repository)).returns(T::Array[String]) }
    def merged_allowlists(billable_owner:, repository:)
      return [] unless billable_owner && repository
      allowlists = get_allowlists(billable_owner:, repository:)

      if Codespaces::PolicyConstraint::CONSTRAINT_CONFIGURATION.dig(policy_name, :allowed_values_wildcard)
        merge_allowlists_with_wildcards(allowlists)
      else
        allowlists.reduce(:&)
      end
    end

    private

    # Returns an array of policy "owners" that should be considered.
    # This always includes the billable_owner, and adds
    # the business for enterprise-wide policy when the feature flag is enabled.
    sig do
      params(
        billable_owner: T.nilable(T.any(User, Organization))
      ).returns(T::Array[T.any(Business, User, Organization)])
    end
    def policy_owners(billable_owner)
      business = billable_owner&.business
      if business && business.feature_flag_enabled_or_raise?(:codespaces_enterprise_policies) && business.in_codespaces_salus_beta? # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        [business, billable_owner]
      else
        [billable_owner].compact
      end
    end

    # Returns an array of policy "targets" that should be considered.
    # This always includes the billable_owner, and optionally includes the repository,
    # which can be excluded to ignore policy targeting "selected repositories". This adds
    # the business for enterprise-wide policy when the feature flag is enabled.
    sig do
      params(
        billable_owner: T.nilable(T.any(User, Organization)),
        repository: T.nilable(Repository),
      ).returns(T::Array[T.any(Business, User, Organization, Repository)])
    end
    def policy_targets(billable_owner:, repository: nil)
      targets = [billable_owner, repository]
      if billable_owner&.business&.feature_flag_enabled_or_raise?(:codespaces_enterprise_policies) && billable_owner&.business&.in_codespaces_salus_beta? # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        targets << billable_owner&.business
      end
      targets.compact
    end

    def value_allowed?(value_name:, billable_owner:, repository:)
      allowlists = get_allowlists(billable_owner:, repository:)
      return true unless allowlists.any?

      allows_wildcard = Codespaces::PolicyConstraint::CONSTRAINT_CONFIGURATION.dig(policy_name, :allowed_values_wildcard)

      allowlists.all? do |allowlist|
        next true if value_name.in?(allowlist)
        # Allows wildcard matches only if the suffix (ie last character of the string) is "*".
        allows_wildcard && allowlist.any? { |v| v.ends_with?("*") && value_name.starts_with?(v.chomp("*")) }
      end
    end

    def get_maximums(billable_owner:, repository:)
      return [] unless Codespaces::OrgPolicy.owning_organization(repository) == billable_owner

      get_constraint_values_for_policy_group_memberships(
        billable_owner:,
        repository:,
        field: :maximum_value
      )
    end

    def get_policy_owner_maximums(billable_owner:)
      return [] unless billable_owner&.organization?

      get_org_level_constraint_values_for_policy_group_memberships(
        billable_owner:,
        field: :maximum_value
      )
    end

    def get_policy_constraints(billable_owner:)
      return [] unless billable_owner&.organization?

      PolicyConstraint.joins(:policy_group_memberships).where(name: policy_name).
        where(policy_group_memberships: { target: policy_targets(billable_owner:) })
    end

    # Returns enterprise and org level constraint values despite the name
    def get_org_level_constraint_values_for_policy_group_memberships(billable_owner:, field:)
      PolicyGroupMembership.joins(:policy_constraints).where(target: policy_targets(billable_owner:)).
        where(policy_constraints: { name:  policy_name }).pluck(field)
    end

    # This method is too specific to the host setup policy constraint, future policy constraints which uses `params` needs to tweak it.
    # Current behavior: For a repo, if there is a policy constraint at the repo level, it will be returned. Else, it returns the org one.
    def get_params(billable_owner:, repository:)
      return [] unless Codespaces::OrgPolicy.owning_organization(repository) == billable_owner

      policies = get_constraint_values_for_policy_group_memberships_with_target_type(
        billable_owner:,
        repository:,
        field: :params
      )

      return [] if policies.nil?
      return policies if policies.length <= 1

      policies.select { |policy| policy.second == "Repository" }
    end

    def get_constraint_values_for_policy_group_memberships_with_target_type(billable_owner:, repository:, field:)
      PolicyGroupMembership.joins(:policy_constraints)
        .where(target: policy_targets(billable_owner:, repository:))
        .where(policy_group: { owner: policy_owners(billable_owner) })
        .where(policy_constraints: { name:  policy_name }).pluck(field, :target_type)
    end

    def get_constraint_values_for_policy_group_memberships(billable_owner:, repository:, field:)
      PolicyGroupMembership.joins(:policy_constraints)
        .where(target: policy_targets(billable_owner:, repository:))
        .where(policy_group: { owner: policy_owners(billable_owner) })
        .where(policy_constraints: { name:  policy_name }).pluck(field)
    end

    def get_policy_group_selected_memberships(policy_group_owner:, entity:)
      PolicyGroupMembership.joins(:policy_constraints).where(target: [entity].compact).
        where(policy_constraints: { name:  policy_name }, policy_group: { owner: policy_group_owner })
    end

    # Iterate over each list in allowlists. For each iteration, compare the values in that list to those in `result`.
    # Any values in the list or `result` that are neither (1) an exact match of a value in the other, nor (2) matched under
    # a wildcard string in the other, are removed from the result. Meanwhile, any values that do find a match are stored
    # in result for the next iteration. Lastly, simplify the final result by removing redundant wildcards.
    sig { params(allowlists: T::Array[T::Array[String]]).returns(T::Array[String]) }
    def merge_allowlists_with_wildcards(allowlists)
      first_list = allowlists.pop || []

      result = allowlists.reduce(first_list) do |output, list|
        merge_lists_with_matches_and_most_specific_wildcards(output, list)
      end

      dedup_wildcards(result)
    end

    sig { params(list1: T::Array[String], list2: T::Array[String]).returns(T::Array[String]) }
    def merge_lists_with_matches_and_most_specific_wildcards(list1, list2)
      list1_to_keep = list1.select do |value|
        value.in?(list2) || list2.any? { |wildcard| matches_wildcard?(value, wildcard) }
      end

      list2_to_keep = list2.select do |value|
        value.in?(list1) || list1.any? { |wildcard| matches_wildcard?(value, wildcard) }
      end

      (list1_to_keep + list2_to_keep).uniq
    end

    sig { params(value: String, wildcard_value: String).returns(T::Boolean) }
    def matches_wildcard?(value, wildcard_value)
      return false unless wildcard_value.ends_with?("*")
      value.chomp("*").starts_with?(wildcard_value.chomp("*")) # Identical or more specific wildcard values match the wildcard, too.
    end

    # For a given list of values (either an explicit string, or a valid "wildcard" string ending with '*'),
    # remove duplicates, any explicit values that are covered by a wildcard, and any wildcards that are covered by another wildcard.
    sig { params(values: T::Array[String]).returns(T::Array[String]) }
    def dedup_wildcards(values)
      values.uniq.reduce([]) do |result, v|
        if values.none? { |r| r != v && matches_wildcard?(v, r) }
          result << v
        end
        result
      end
    end
  end
end
