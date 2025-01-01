# typed: strict
# frozen_string_literal: true

module Copilot
  module ContentExclusion
    module DocumentErrorHelpers

      private

      sig { params(element: Document::ELEMENT).void }
      def validate_path_pattern!(element)
        pattern = T.let(element[:value], String)

        # Negated rules is not supported.
        # negated rules are patterns that start with a `!` and are not followed by a `[` or `(`.
        # eg: `!(1|2)3` is valid, as that means "43" ✅ but "23" ❌
        # but dont allow `!test` as that says "anything except 'test'"
        report_error("Negated patterns not supported", element[:location]) if /\A![^\[\(]/.match?(pattern)
      end

      sig { params(repo: Document::ELEMENT).void }
      def validate_repo_url!(repo)
        return if repo[:value] == "*"

        return if ContentExclusion::GITHUB_OWNER_AND_OR_REPO_NAME_VALID_REGEX.match?(repo[:value])

        repo_name_error = Copilot::ContentExclusion::UrlNormalizer.new.normalize(repo[:value]).error
        report_error(repo_name_error.message, repo[:location]) if repo_name_error
      end

      sig { params(message: String, node: Psych::Nodes::Node).void }
      def report_node_error(message, node)
        report_error(message, [node.start_line, node.start_column])
      end

      sig { params(message: String, location: [Integer, Integer]).void }
      def report_error(message, location)
        # line,cols are zero-index — presentationally lets show them as one-index
        Kernel.raise Document::ParsingError, error_message(message, location[0] + 1, location[1] + 1)
      end

      sig { params(message: String, line: Integer, column: Integer).returns(String) }
      def error_message(message, line, column)
        "Error on line #{line}, column #{column}: #{message}"
      end
    end
  end
end
