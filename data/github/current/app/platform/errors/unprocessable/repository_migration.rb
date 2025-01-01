# typed: true
# frozen_string_literal: true

module Platform
  module Errors
    class Unprocessable
      class RepositoryMigration < Errors::Execution
        def initialize(*args, **options)
          T.unsafe(Errors::Execution.instance_method(:initialize)).bind(self).call("REPOSITORY_MIGRATION", "Repository has been locked for migration", *args, **options)
        end
      end
    end
  end
end
