# typed: strict
# frozen_string_literal: true

module Repositories
  class Domain
    class CustomProperties < GH::Domain::Base
      # This method is a wrapper around `values_for_repos` and `values_hash_to_string_hash`.
      # It calls `values_for_repos` followed by `values_hash_to_string_hash`
      # It provides a shortcut for the cases when we only need to get key value pairs for each repo.
      # It returns a hash of property values for each repo.
      #
      # repos - repos objects
      # value_to_use - One of `:manual` or `:effective`
      # strip_nils - If true (defaults to false), any properties with a nil value will be completely stripped from the
      #   returned hash
      sig do
        params(
          repos: T::Enumerable[IRepository],
          value_to_use: Symbol,
          strip_nils: T::Boolean
        ).returns(T::Hash[IRepository, T::Hash[String, T.nilable(::CustomProperties::PropertyValue)]]).checked(:always).on_failure(:raise)
      end
      def repo_properties(repos, value_to_use, strip_nils: false)
        values_hash_to_string_hash(values_for_repos(repos), value_to_use, strip_nils:)
      end

      # Returns a hash of properties that apply for each input repo. Repos passed in are returned untouched as the
      # keys of the hash.
      #
      # The array of properties for each repo will be sorted by property name.
      sig do
        params(
          repos: T::Enumerable[IRepository]
        ).returns(RepoPropertyValueHash)
        .checked(:always).on_failure(:raise)
      end
      def values_for_repos(repos) # rubocop:todo Metrics/MethodLength
        return {} unless repos.any?

        repo_ids = repos.map(&:id)
        owners = repos.map(&:owner)

        if owners.any? { |owner| !owner&.organization? }
          raise ArgumentError, "all repos must belong to an organization"
        end

        org_ids = owners.map { |owner| owner&.id }.uniq
        biz_ids = owners.map { |owner| T.cast(owner, Orgs::IOrganization).business&.id }.uniq

        # merge all definitions with configured values for each. don't use `includes(:custom_property_values)`
        # because that may query more rows than are needed
        defs_by_org = CustomPropertyDefinition.where(source_id: org_ids, source_type: :org).group_by(&:source_id)
        defs_by_biz = if biz_ids.any?
          CustomPropertyDefinition.where(source_id: biz_ids, source_type: :business).group_by(&:source_id)
        else
          {}
        end
        # At this point we don't know if user needs effective or manual value, but we won't to provide a consistent order for the values
        set_values_by_target = CustomPropertyValue.where(target_id: repo_ids).order(value: :asc).group_by(&:target_id)

        repos.to_h do |repo|
          values_by_repo_def = set_values_by_target.fetch(repo.id, []).group_by(&:definition_id)

          biz_id = T.cast(repo.owner, Orgs::IOrganization)&.business&.id
          biz_defs = biz_id ? defs_by_biz.fetch(biz_id, []) : []

          org_defs = defs_by_org.fetch(repo.owner&.id, [])

          definitions = CustomPropertiesDefinitionsManager.merge_definitions(biz_defs, org_defs)
          prop_array = definitions.flat_map do |defn|
            # check all set values to see if one exists for this definition and repo
            values = values_by_repo_def.fetch(defn.id, [])
            ValueWithDefinition.new(defn, values)
          end

          [repo, prop_array]
        end
      end

      # Takes the result of `values_for_repos` and returns a hash of property values for each repo.
      #
      # value_hash - The result of `values_for_repos`
      # value_to_use - One of `:manual` or `:effective`
      # strip_nils - If true (defaults to false), any properties with a nil value will be completely stripped from the
      #   returned hash
      sig do
        params(
          value_hash: RepoPropertyValueHash,
          value_to_use: Symbol,
          strip_nils: T::Boolean
        ).returns(T::Hash[IRepository, T::Hash[String, T.nilable(::CustomProperties::PropertyValue)]])
        .checked(:always).on_failure(:raise)
      end
      def values_hash_to_string_hash(value_hash, value_to_use, strip_nils: false) # rubocop:todo Metrics/MethodLength
        allowed_values_to_use = [:manual, :effective]
        unless allowed_values_to_use.include?(value_to_use)
          raise ArgumentError, "invalid value specified for value_to_use: #{value_to_use}"
        end

        value_hash.transform_values do |properties|
          values = properties.to_h do |value|
            val = if value_to_use == :manual
              value.manual_value
            else
              value.effective_value
            end

            [value.definition.property_name, val]
          end

          values = values.compact if strip_nils
          values
        end
      end

      # Public: Returns whether the given user can see property definitions for the given org.
      #
      # user - The user to check permissions for
      # org - The org to check permissions for
      sig do
        params(
          user: ::CustomProperties::AuthzdActor,
          org: Organization
        ).returns(T::Boolean)
        .checked(:always).on_failure(:raise)
      end
      def can_see_property_definitions?(user, org)
        if user.can_have_granular_permissions?
          org.resources.organization_custom_properties.readable_by?(user)
        else
          org.member?(user)
        end
      end

      RepoPropertyValueHash = T.type_alias { T::Hash[IRepository, T::Array[::CustomProperties::IPropertyValue]] }
    end
  end
end
