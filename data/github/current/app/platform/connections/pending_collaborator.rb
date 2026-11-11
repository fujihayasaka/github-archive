# typed: true
# frozen_string_literal: true

module Platform
  module Connections
    class PendingCollaborator < Connections::Base
      description "A list of pending repository collaborators for an account."
      visibility :internal

      total_count_field
    end
  end
end
