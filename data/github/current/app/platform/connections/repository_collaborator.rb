# typed: true
# frozen_string_literal: true

module Platform
  module Connections
    class RepositoryCollaborator < Connections::Base
      minimum_accepted_scopes ["public_repo"]

      total_count_field

      def total_count
        @object.collaborators_count || super
      end
    end
  end
end
