# typed: true
# frozen_string_literal: true

module Platform
  module Edges
    class PendingCollaborator < Edges::Base
      description "Represents a pending collaborator on a repository."
      visibility :internal

      node_type Objects::User

      field :pending_invitations, Connections.define(Objects::RepositoryInvitation), visibility: :internal, description: "The pending invitations for a pending collaborator.", null: false, connection: true

      def pending_invitations
        user = @object.node
        org = @object.parent

        Platform::Loaders::OrgPendingRepositoryInvitation.load(org, user.id)
      end
    end
  end
end
