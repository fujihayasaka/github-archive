# typed: false
# frozen_string_literal: true

module Platform
  module Errors
    class Unprocessable
      class RepositoryMigration < Errors::Execution
        def initialize(*args, **options)
          super("REPOSITORY_MIGRATION", "Repository has been locked for migration", *args, **options)
        end
      end
    end
  end
end
