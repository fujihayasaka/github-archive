# typed: true
# frozen_string_literal: true
require "open3"
require "parser/current"
require "active_support/inflector"

module GitHub
  class BonesExporter
    class TestSuiteParser
      attr_accessor :path, :source

      def initialize(path, source = nil)
        @path = path
        @source = source
      end

      def class_name(node)
        # handle class node:
        # Ruby:
        # class GitHubFailbotFilterKeyTest < Test::Fast::TestCase
        #
        # exp:
        #  s(:const,
        #    s(:const, nil, :GitHub), :TestCase)

        suite_class, suite_super, suite_body = *node.children

        names = [suite_class.source]

        # traverse backwards up to root node to find classes/modules in namespace
        parent = node.parent
        while parent
          parent_class, parent_super, parent_body = *parent.children

          if parent.module_type? || parent.class_type?
            names << parent_class.source
          end

          parent = parent.parent
        end

        # names is backwards, so reverse it
        names.reverse.join("::")
      end

      def parse
        parser        = Parser::CurrentRuby.new(builder)
        buffer        = Parser::Source::Buffer.new(path)
        buffer.source = if source
          source
        else
          File.read(path)
        end

        root_node     = parser.parse(buffer)
        extract_suite_nodes(root_node).map do |suite_node|
          class_name(suite_node)
        end
      end

      def builder
        begin
          require "rubocop"
          RuboCop::AST::Builder.new
        rescue LoadError
          raise "rubocop unavailable in current environment"
        end
      end

      def extract_suite_nodes(node)
        return [] unless node

        suite_nodes = []
        suite_nodes << node if test_suite?(node)

        node.child_nodes.each do |child|
          suite_nodes.concat extract_suite_nodes(child)
        end

        suite_nodes
      end

      def test_suite?(node)
        return false unless node.class_type?

        suite_class, suite_super, suite_body = *node.children
        return false unless suite_super

        return true if suite_super.source.end_with?("TestCase")
        return true if suite_super.source.end_with?("Test")
        # FIXME need to handle describe like in CheckListItem test

        false
      end
    end

  end
end
