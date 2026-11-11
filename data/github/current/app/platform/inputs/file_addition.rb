# typed: strict
# frozen_string_literal: true

module Platform
  module Inputs
    class FileAddition < Platform::Inputs::Base
      graphql_name "FileAddition"
      description "A command to add a file at the given path with the given contents as part of a commit.  Any existing file at that that path will be replaced."

      argument :path, String, "The path in the repository where the file will be located", required: true
      argument :contents, Scalars::Base64String, "The base64 encoded contents of the file", required: true
    end
  end
end
