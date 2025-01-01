# typed: strict
# frozen_string_literal: true

module Copilot
  module Repositories
    class ContentExclusionDocument < Copilot::ContentExclusion::Document

      private

      sig { returns(GitHub::Result) }
      def process
        doc = Psych.parse_stream(@document).children.first

        GitHub::Result.new do
          report_node_error("Expecting a document", doc) unless doc.document?

          # First let's assume the first child of the document is a sequence of paths
          root = doc.children.first

          # Seeing as we only care about the first array, let's assert that—that is the case.
          report_node_error("Expecting an array of paths", root) unless root.is_a?(Psych::Nodes::Sequence)

          # Now that we know we have an array of stuff:
          # - "mona"
          # - "smile"

          rule = Copilot::ContentExclusion::Rule.new(allow_text_based_rules: @allow_text_based_rules)

          root.children.each { |node| rule.add_policies_from_node(node) }

          [rule]
        end
      rescue Psych::SyntaxError => e
        GitHub::Result.error ParsingError.new(error_message(e.problem, e.line, e.column))
      end
    end
  end
end
