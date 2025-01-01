# typed: true
# frozen_string_literal: true

require "open3"
require "prism"

require "serviceowners/parse_error"

module Serviceowners
  module Internal
    # Extracts class and module names from a Ruby file.
    # Unless supplied directly, the source code is read from the given file system path.
    class ClassParser
      attr_accessor :path, :source

      def initialize(path, source = nil)
        @path = path
        @source = source
      end

      def parse
        parsed = Prism.parse(source || File.read(path))
        raise Serviceowners::ParseError, "problem parsing #{path}" unless parsed.errors.empty?

        classes = []
        parsed.value.accept(ClassVisitor.new(classes))
        classes
      end

      # Visitor that extracts class and module names from the visited nodes
      class ClassVisitor < Prism::Visitor
        def initialize(classes)
          super()
          @classes = classes
          @namespace = []
        end

        def visit_class_node(node)
          @namespace << node.constant_path.full_name
          @classes << @namespace.join("::")

          super

          @namespace.pop
        end

        def visit_module_node(node)
          @namespace << node.constant_path.full_name
          @classes << @namespace.join("::")

          super

          @namespace.pop
        end
      end
    end
  end
end
