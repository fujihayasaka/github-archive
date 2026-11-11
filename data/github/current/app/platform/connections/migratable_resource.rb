# typed: true
# frozen_string_literal: true

module Platform
  module Connections
    class MigratableResource < Connections::Base
      description "Get a list of migratable resource mappings to audit a migration."

      total_count_field
    end
  end
end
