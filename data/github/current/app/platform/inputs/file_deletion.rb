# typed: strict
# frozen_string_literal: true

module Platform
  module Inputs
    class FileDeletion < Platform::Inputs::Base
      graphql_name "FileDeletion"
      description "A command to delete the file at the given path as part of a commit."

      argument :path, String, "The path to delete", required: true
    end
  end
end
