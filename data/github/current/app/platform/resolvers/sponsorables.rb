# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class Sponsorables < Resolvers::Base
      type Connections.define(Unions::SponsorableItem), null: false

      def resolve(**arguments)
        sponsorable_user_ids = ::SponsorsListing
          .with_approved_state
          .pluck(:sponsorable_id)

        users = ::User.where(id: sponsorable_user_ids)
          .filter_spam_for(context[:viewer])

        if order_by = arguments[:order_by]
          field = order_by[:field]
          direction = order_by[:direction]

          users = users.order(field => direction)
        end

        if arguments[:only_dependencies]
          unless context[:viewer]
            raise Errors::Forbidden.new("Must be authenticated to filter to sponsorable owners " \
              "of your dependencies or the dependencies of a specified organization.")
          end

          org_login = arguments[:org_login_for_dependencies]
          ecosystems = [arguments[:ecosystem] || arguments[:dependency_ecosystem]].compact_blank.map(&:upcase)

          if org_login.present?
            async_load_organization(org_login).then do |org|
              async_filter_to_dependency_owners(users, ecosystems: ecosystems, owner: org)
            end
          else
            async_filter_to_dependency_owners(users, ecosystems: ecosystems, owner: context[:viewer])
          end
        else
          users
        end
      end

      private

      def async_load_organization(login)
        Loaders::ActiveRecord.load(::Organization, login,
          column: :login,
          case_sensitive: false,
        ).then do |org|
          if org && !org.hide_from_user?(context[:viewer])
            org
          else
            raise Errors::NotFound, "Could not resolve to an Organization with the login " \
              "of '#{login}'."
          end
        end
      end

      def async_filter_to_dependency_owners(users, ecosystems:, owner:)
        dependencies_loader = dependencies_loader_for(owner, package_managers: ecosystems)

        dependencies_loader.async_dependencies(scope: ::Repository.with_sponsorable_owner).then do |result|
          dependency_repos = result.dependencies
          next ::User.none if dependency_repos.empty?

          dependency_owner_ids = dependency_repos.map(&:owner_id).uniq
          users.where(id: dependency_owner_ids)
        end
      end

      def dependencies_loader_for(owner, package_managers:)
        owner_adminable_by_viewer = owner == context[:viewer] ||
          owner.adminable_by?(context[:viewer])

        Repository::OwnerDependenciesLoader.new(
          owner_id: owner.id,
          public_only: !owner_adminable_by_viewer,
          package_managers: package_managers.map(&:upcase),
          sort_by: nil,
          direct_only: false,
          viewer: context[:viewer],
        )
      end
    end
  end
end
