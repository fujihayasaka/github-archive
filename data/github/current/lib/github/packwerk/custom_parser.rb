# typed: true
# frozen_string_literal: true

require "packwerk"
require "parser/source/buffer"

module GitHub
  module Packwerk
    class CustomParser < ::Packwerk::Parsers::Erb
      def parse_buffer(buffer, file_path:)
        preprocessed_source = buffer.source

        # Comment out <%graphql ... %> tags. They won't contain any object
        # references anyways.
        preprocessed_source = preprocessed_source.gsub(/<%graphql/, "<%#")

        # We have some places that do:
        #   <%= ... =%>
        # Erubi will happily parse that and ignore the trailing `=` but Packwerk
        # won't, so convert it to the more standard form:
        #   <%= ... %>
        preprocessed_source = preprocessed_source.gsub(/=%>/, "%>")

        preprocessed_buffer = Parser::Source::Buffer.new(file_path)
        preprocessed_buffer.source = preprocessed_source
        super(preprocessed_buffer, file_path: file_path)
      end
    end

    ::Packwerk::Parsers::Factory.instance.erb_parser_class = CustomParser
  end
end
