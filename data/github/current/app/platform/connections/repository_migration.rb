# typed: true
# frozen_string_literal: true

module Platform
  module Connections
    class RepositoryMigration < Connections::Base
      description "A list of migrations."

      total_count_field
    end
  end
end
