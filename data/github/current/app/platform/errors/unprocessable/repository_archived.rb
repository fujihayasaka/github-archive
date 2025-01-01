# typed: false
# frozen_string_literal: true

module Platform
  module Errors
    class Unprocessable
      class RepositoryArchived < Errors::Execution
        def initialize(*args, **options)
          super("REPOSITORY_ARCHIVED", "Repository was archived so is read-only.", *args, **options)
        end
      end
    end
  end
end
