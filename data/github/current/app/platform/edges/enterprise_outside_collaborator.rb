# typed: true
# frozen_string_literal: true

module Platform
  module Edges
    class EnterpriseOutsideCollaborator < Edges::Base
      include Scientist

      node_type Objects::User
      description "A User who is an outside collaborator of an enterprise through one or more organizations."

      field :repositories, Connections.define(Objects::EnterpriseRepositoryInfo), null: false,
        description: "The enterprise organization repositories this user is a member of." do
        argument :order_by, Inputs::RepositoryOrder,
          "Ordering options for repositories.",
          required: false, default_value: { field: "name", direction: "ASC" }
      end

      def repositories(order_by: nil)
        user = object.node
        business = object.parent

        # This maps to `Platform::Models::EnterpriseRepositoryInfo` to avoid
        # permissions checks on the `Repository` object.  Enterprise admins
        # won't necessarily have read permissions on repos but we still want
        # to allow them to read repository names here
        # This should be looked at again before making business GraphQL public
        repos = user.outside_collaborator_repositories(business: business)

        unless order_by.nil?
          repos = repos.order("repositories.#{order_by[:field]} #{order_by[:direction]}")
        end

        repos = repos.map { |repo| Platform::Models::EnterpriseRepositoryInfo.new(repo, business) }
        ArrayWrapper.new(repos)
      end
    end
  end
end
