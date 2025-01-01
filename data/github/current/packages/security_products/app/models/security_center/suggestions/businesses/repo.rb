# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module Suggestions
    module Businesses
      class Repo < Base

        sig { params(authorized_orgs: T::Array[Organization], business: Business, user: User, kwargs: T.untyped).void }
        def initialize(authorized_orgs:, business:, user:, **kwargs)
          super(**T.unsafe(kwargs))
          @authorized_orgs = authorized_orgs
          @business = business
          @user = user
        end

        sig { override.returns(T::Array[Suggestion]) }
        memoize def suggestions
          # Short-circuit if the user is not authorized to view any orgs
          # **and** the business does not support emu repos.
          return [] if @authorized_orgs.blank? && !include_emus?

          # If `value` is of the form "owner/repo", then match "repo" to repos for that owner only.
          #
          # If `value` does not have a "/", we don't know if the user is looking for owners or repos.
          # Therefore, find all owners OR repos matching `value`.
          repo_config_rel =
            if value.include?("/")
              exact_owner_and_repo_suggestions_rel
            else
              owner_or_repo_suggestions_rel
            end

          repo_rel = without_selected_values_rel(repo_config_rel)
            .select(:repository_id)
            .order(:name)

          repo_rel = repo_rel.limit(limit) if limit.present?

          # Must calculate IDs first as mysql does not allow
          # using LIMIT inside an IN clause.
          repo_ids = repo_rel.pluck(:repository_id)
          return [] if repo_ids.blank?

          repo_rel = Repository
            .active
            .where(id: repo_ids)
            .select(:id, :name, :owner_id, :owner_login)
            .includes(:owner)
            .order(:name, :owner_login)

          repo_rel.map do |repo|
            Suggestion.new(
              description: repo.owner_display_login,
              label: repo.name,
              value: repo.name_with_display_owner
            )
          end
        end

        sig { returns(ActiveRecord::Relation) }
        memoize def all_configs_accessible_to_user_rel
          SecurityOverviewAnalytics::Dashboards::EnterpriseReposFilterer
            .new(
              business: @business,
              organizations: @authorized_orgs,
              query: ::Search::Queries::SecurityCenter::QueryParser.new(""),
              user: @user,
            )
            .any_feature_repo_metadata_rel
        end

        # Given a search value such as "{owner}/{submatch}"
        # First look for an exact match against the owner,
        # Then look for any repo names that match the submatch
        sig { returns(ActiveRecord::Relation) }
        def exact_owner_and_repo_suggestions_rel
          owner_name, repo_name = value.split("/", 2)
          owner_ids = owner_suggestion_ids(T.must(owner_name))
          return RepositorySecurityCenterConfig.none if owner_ids.blank?

          rel = all_configs_accessible_to_user_rel.where(owner_id: owner_ids)
          rel = rel.where("name LIKE ?", "%#{repo_name}%") if repo_name.present?
          rel
        end

        # Given a search value such as "{submatch}"
        # Look for any repo names that match the submatch
        # Or authorized orgs that match the submatch
        # Or, if applicable, EMUs that match the submatch
        sig { returns(ActiveRecord::Relation) }
        def owner_or_repo_suggestions_rel
          rel = all_configs_accessible_to_user_rel
          return rel if value.blank?

          # repo suggestions
          repo_suggestions = rel.where("name LIKE ?", "%#{value}%")

          owner_ids = owner_suggestion_ids(value, submatch: true)
          return repo_suggestions if owner_ids.blank?

          rel.and(repo_suggestions.or(rel.where(owner_id: owner_ids)))
        end

        sig { params(repo_rel: ActiveRecord::Relation).returns(ActiveRecord::Relation) }
        def without_selected_values_rel(repo_rel)
          return repo_rel if selected_values.blank?

          selected_repo_ids = Repository.with_names_with_owners(selected_values).pluck(:id)
          repo_rel.where.not(repository_id: selected_repo_ids)
        end

        sig { returns(T::Boolean) }
        memoize def include_emus?
          business_authz = ::SecurityProduct::Permissions::BusinessAuthz.new(@business, actor: @user)
          return false unless business_authz.can_view_user_owned_repository_alerts?
          AdvancedSecurity::Features::Business::AdvancedSecurity.new(@business).feature_available_for_user_repositories?
        end

        # If submatch is false, look for an exact match against authorized orgs or an EMU
        # If submatch is true, look for any orgs or emus that look like the `name`
        sig { params(name: String, submatch: T::Boolean).returns(T::Array[Integer]) }
        def owner_suggestion_ids(name, submatch: false)
          # Look for an owner explicitly matching "name"
          unless submatch
            org_ids = @authorized_orgs
              .select { |o| o.display_login == name }
              .map { |o| o.id }
            return org_ids if org_ids.present?

            # Make sure we should be looking for emus
            return [] unless include_emus?

            user_id = find_emus(name, submatch:)
            return user_id
          end

          # Fuzzy match "name" against authorized orgs and emus
          org_ids = @authorized_orgs
            .select { |o| o.display_login.include?(value) }
            .map { |o| o.id }

          # Make sure we should be looking for emus
          return org_ids unless include_emus?

          # include emu results
          user_ids = find_emus(name, submatch: true)
          org_ids | user_ids
        end

        # find_emus tries to find users by their login name
        # This will return up to `limit` users that match the `name`
        sig { params(name: String, submatch: T::Boolean).returns(T::Array[Integer]) }
        def find_emus(name, submatch: false)
          if submatch
            needle = "%#{name}%"
            search = "login LIKE ?"
          else
            needle = name
            search = "login = ?"
          end

          if GitHub.enterprise?
            User
              .where(type: "User")
              .where(search, needle)
              .not_suspended
              .limit(limit)
              .pluck(:id)
          else
            BusinessUserAccount
              .where(business_id: @business.id)
              .where(search, needle)
              .limit(limit)
              .pluck(:user_id)
          end
        end
      end
    end
  end
end
