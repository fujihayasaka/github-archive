# typed: strict
# frozen_string_literal: true

module Copilot
  module Organizations
    class ContentExclusionDocument < Copilot::ContentExclusion::Document

      private

      sig { returns(GitHub::Result) }
      def process
        doc = Psych.parse_stream(@document).children.first

        GitHub::Result.new do
          report_node_error("Expecting a document", doc) unless doc.document?

          rules = T.let([], T::Array[Copilot::ContentExclusion::Rule])

          # First let's assume the first child of the document is a repo to path mapping.
          root = doc.children.first

          # to to that, let's assert this first child is a mapping
          report_node_error("Expecting an mapping of repositories", root) unless root.is_a?(Psych::Nodes::Mapping)

          # Now that we know we have a mapping, where the `doc.children.first` item is:
          #   first_entry: [a, b, c]
          #   second_entry: "mona"

          # we are still unsure if it is of a valid shape — so let us start traversing it:
          root.children.each_slice(2) do |key, value|
            report_node_error("Expecting a repository reference", key) unless key.is_a?(Psych::Nodes::Scalar)
            report_node_error("Expecting an array of rule configurations", value) unless value.is_a?(Psych::Nodes::Sequence)

            validate_repo_url!({ value: key.value, location: [key.start_line, key.start_column] })
            rules << rule = Copilot::ContentExclusion::Rule.new(scope: key.value, allow_text_based_rules: @allow_text_based_rules)

            T.let(value, Psych::Nodes::Sequence).children.each { |item| rule.add_policies_from_node(item) }
          end

          rules
        end
      rescue Psych::SyntaxError => e
        GitHub::Result.error ParsingError.new(error_message(e.problem, e.line, e.column))
      end
    end
  end
end
