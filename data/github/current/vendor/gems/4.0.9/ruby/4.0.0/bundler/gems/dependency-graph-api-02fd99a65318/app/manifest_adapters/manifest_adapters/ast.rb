module ManifestAdapters
  class Ast
    module Languages
      PYTHON = "tree_sitter_python"
    end

    def initialize(content, language: Languages::PYTHON)
      @content = content
      @language = language
    end

    def walker
      Walker.new(self).to_enum
    end

    def text(node)
      return unless node

      node.text(@content)
    end

    def document
      @document ||= parse_document
    end

    def parse_document
      document = TreeSitter::Document.new(@content, language: @language)
      document.parse
      document
    end

    def null_node
      NullNode.new
    end

    def null_children
      ChildrenWrapper.new([], self)
    end

    def find(node_type:, text:)
      walker = self.walker

      while node = walker.next do
        if node.node_type == node_type
          if node.named_children[0].named_children[0].text == text
            return node
          end
        end
      end
    rescue StopIteration
      null_node
    end

    # NodeWrapper wraps raw TreeSitter::Nodes to provide some traversal
    # convenience methods.
    class NodeWrapper
      attr_reader :node

      def initialize(node, ast)
        @node = node
        @ast = ast
      end

      def named_children
        ChildrenWrapper.new(node.named_children, @ast)
      end

      def node_type
        node.node_type
      end

      def text
        @ast.text(node)
      end

      def to_s
        node.to_s
      end
    end

    class ChildrenWrapper
      include Enumerable

      def initialize(children, ast)
        @children = children
        @ast = ast
      end

      def [](n)
        NodeWrapper.new(@children[n] || NullNode.new, @ast)
      end
      alias :at :[]

      def each(&block)
        @children.map { |child| NodeWrapper.new(child, @ast) }.each(&block)
      end

      def to_s
        @children.map(&:to_s).join(", ")
      end

      def filter(node_type)
        children = @children.select { |child| child.node_type == node_type }
        ChildrenWrapper.new(children, @ast)
      end
    end

    class NullNode
      def node_type; end

      def text; end

      def named_children
        ChildrenWrapper.new([], nil)
      end
    end

    class Walker
      def initialize(ast, max_depth = 10)
        @ast = ast
        @root = @ast.document.root_node
        @max_depth = max_depth
      end

      # TODO: Breadth-first would probably be better than depth-first.
      def each(node = @root, depth = 0, &block)
        return if depth > max_depth

        block.call(NodeWrapper.new(node, @ast))

        node.named_children.each do |child|
          each(child, depth + 1, &block)
        end
      end

      private

      attr_reader :max_depth
    end
  end
end
