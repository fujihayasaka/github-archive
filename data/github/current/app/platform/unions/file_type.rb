# typed: strict
# frozen_string_literal: true

module Platform
  module Unions
    class FileType < Platform::Unions::Base
      description "TreeEntry file types."

      mobile_only true

      possible_types Objects::ImageFileType, Objects::MarkdownFileType, Objects::PdfFileType, Objects::TextFileType
    end
  end
end
