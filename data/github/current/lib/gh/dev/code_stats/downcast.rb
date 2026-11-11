# typed: strict
# frozen_string_literal: true

require "code_stats"
require "gh/dev/code_stats/base"
require "rubocop"
require "rubocop-ast"

module GH
  module Dev
    class CodeStats
      class Downcast < Base
        PACKAGE_NAME_REGEX = T.let(/(packages\/\S+?)\//.freeze, Regexp)
        RUBOCOP_COMMENTS = T.let(
          [
            "rubocop:todo GitHub/AvoidCast",
            "rubocop:disable GitHub/AvoidCast",
          ].freeze,
          T::Array[String]
        )

        UNKNOWN_PACKAGE = T.let("unknown".freeze, String)

        sig { override.void }
        def report_data!
          packages_with_avoid_cast = T.let([], T::Array[String])

          each_source do |source, path|
            source.ast.each_node do |node|
              next unless node.children[1] == :cast

              line_comments = source.each_comment_in_lines(node.loc.line - 1..node.loc.last_line).to_a.map(&:text)
              has_avoid_cast = line_comments.any? { |comment| RUBOCOP_COMMENTS.any? { |c| comment.include?(c) } }
              next unless has_avoid_cast

              process_node(packages_with_avoid_cast, node, path)
            end
          end

          packages_with_avoid_cast.tally.each do |package, count|
            owning_package, calling_package = package.split("#")
            tags = ["package:#{owning_package}", "calling_package:#{calling_package}"]
            report.gauge("code_stats.downcast.lines", count, tags)
          end
        end

        private

        sig { params(block: T.proc.params(_arg0: RuboCop::ProcessedSource, _arg1: String).void).void }
        def each_source(&block)
          Find.find(".") do |path|
            next unless path.end_with?(".rb")

            code = File.read(path)
            next unless RUBOCOP_COMMENTS.any? { |rule| code.include?(rule) }

            source = RuboCop::ProcessedSource.new(code, RUBY_VERSION.to_f, parser_engine: :parser_prism)
            yield(source, path)
          end
        end

        sig { params(packages: T::Array[String], node: RuboCop::AST::Node, source_path: String).void }
        def process_node(packages, node, source_path)
          return unless node.is_a?(RuboCop::AST::Node)

          if node.const_type?
            const_type = node.const_name
            return nil if const_type == "T" || const_type == "Promise"

            path, _ = Object.const_source_location(const_type)
            return UNKNOWN_PACKAGE unless path

            owning_package = path_to_package(path)
            calling_package = path_to_package(source_path)
            packages << "#{owning_package}##{calling_package}"
          elsif node.send_type?
            node.child_nodes.each { |child| process_node(packages, child, source_path) }
          end
        end

        sig { params(path: String).returns(String) }
        def path_to_package(path)
          match = path.match(PACKAGE_NAME_REGEX)
          return "_root" if match.nil?

          match.captures.first || "unknown"
        end
      end
    end
  end
end
