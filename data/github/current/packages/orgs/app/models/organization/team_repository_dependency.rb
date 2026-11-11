# typed: true
# frozen_string_literal: true

module Organization::TeamRepositoryDependency
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { Organization }

  included do
    T.bind(self, T.class_of(Organization))

    # this batch method is extracted from Platform::ConnectionWrappers::TeamRepositories and is not intended for genreal purpose enumeration
    batch_method(:repositories_for_team_repo_connection) do |orgs, viewer, query_string, order_by, extra_fields|
      orgs = Array.wrap(orgs)
      query_string = query_string.to_s.strip.downcase
      order_by ||= {}
      extra_fields ||= []

      scope = ::Repository.active.where(owner: orgs).where("owner_id = organization_id")

      query = ActiveRecord::Base.sanitize_sql_like(query_string)
      if query.present?
        scope = scope.where(["repositories.name LIKE ?", "%#{query}%"])
      end

      # If we know there is no viewer, we can ignore any private repositories
      scope = scope.public_scope unless viewer
      scope = scope.filter_spam_and_disabled_for(viewer)
      scope = scope.order(order_by) if order_by
      repos = scope.pluck(:owner_id, :public, :id, extra_fields)

      orgs.index_with do |org|
        repos.select { |repo| repo[0] == org.id }.map { |fields| fields[1...] }
      end
    end
  end
end
