# typed: strict
# frozen_string_literal: true

module Platform
  module Unions
    class FileType < Platform::Unions::Base
      docs_category :meta
      description "TreeEntry file types."

      required_capabilities [:mobile_only_schema_mask, :access_pull_request_diff_graphql_api]

      possible_types Objects::ImageFileType, Objects::MarkdownFileType, Objects::PdfFileType, Objects::TextFileType
    end
  end
end
