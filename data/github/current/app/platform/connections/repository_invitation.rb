# typed: strict
# frozen_string_literal: true

module Platform
  module Connections
    class RepositoryInvitation < Connections::Base
      description "A list of repository invitations."

      total_count_field
    end
  end
end
