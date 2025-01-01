# typed: true
# frozen_string_literal: true

require "prism"
require "action_view"

module GitHub
  module PrismFastRenderEnhancer
    extend T::Helpers
    extend T::Sig
    include Kernel
    abstract!

    attr_accessor :template_resolver

    sig { abstract.params(code: String).void }
    def add_code(code); end

    def self.cache
      @cache ||= Hash.new
    end

    class TemplateResolver
      def template_method(path, locals)
        controller = T.unsafe(ApplicationController).new

        # Hold reference to ActionView::Template to avoid finalizer undefining compiled method.
        # If we have a single template then we can optimize rendering it. Otherwise
        # leave the code unchanged to let Rails handle the rendering.
        template = FastRenderEnhancer.cache[[path, locals]] ||=
          begin
            templates = controller.lookup_context.find_all(path, [], true, locals, {})
            if templates.size == 1
              templates[0]
            else
              nil
            end
          end

        return nil unless template
        unless template.instance_variable_get(:@compile_mutex).locked?
          template.send(:compile!, controller.view_context)
        end

        return if template.nil? || template.strict_locals?

        template.send(:method_name)
      rescue ActionView::MissingTemplate
        raise "Could not resolve partial: #{path.inspect}"
      end
    end

    class RenderRewriter < Prism::BasicVisitor
      attr_reader :buffer

      def initialize(template_resolver = nil)
        @template_resolver = template_resolver || TemplateResolver.new
        @unsupported = nil
        @buffer = +""
      end

      def visit_program_node(node)
        # only visit child nodes if there is only one call node at the top of the tree.
        if node.statements.body.size == 1
          case node.statements.body.first
          when Prism::CallNode, Prism::IfNode, Prism::UnlessNode
            visit(node.statements.body.first)
          end
        end
        @buffer
      end

      def visit_statements_node(node)
        visit_all(node.child_nodes)
      end

      def visit_call_node(node)
        if node.name != :render || node.arguments.nil?
          @unsupported = :no_arguments
          return
        end

        # Extract render arguments
        @locals = []
        @locals_source = "{}"

        @has_block = node.block

        visit(node.arguments)

        return if @unsupported || @partial.nil?

        if @has_block
          visit(node.block)
        else
          method_name = @template_resolver.template_method(@partial, @locals)
          return unless method_name
          method_call = "#{method_name}(#{@locals_source}, @output_buffer) { |*name| self._layout_for(*name) }"
          push method_call
        end
      end

      def visit_if_node(node)
        visit(node.statements)
        return if @unsupported || @partial.nil?

        push " if #{node.predicate.slice}"
      end

      def visit_unless_node(node)
        visit(node.statements)
        return if @unsupported || @partial.nil?

        push " unless #{node.predicate.slice}"
      end

      def visit_arguments_node(node)
        if node.arguments.size < 1 || node.arguments.size > 2
          @unsupported = :unsupported_arguments
          return
        end

        first_argument = node.arguments.first

        case first_argument
        when Prism::StringNode
          @partial = first_argument.unescaped

          if node.arguments.size == 2
            case node.arguments.last
            when Prism::KeywordHashNode, Prism::HashNode
              extract_locals(node.arguments.last)
            else
              @unsupported = :undeterminable_second_argument
            end
          end
        when Prism::KeywordHashNode, Prism::HashNode
          first_argument.elements.each do |assoc|
            assoc = T.cast(assoc, Prism::AssocNode)
            key = T.cast(assoc.key, Prism::SymbolNode)
            case key.value
            when "partial"
              if @partial
                # already specified layout, not allowed
                @unsupported = :layout_and_partial
                return
              end

              if @has_block
                @unsupported = :has_block
                return
              end

              assoc_val = assoc.value
              case assoc_val
              when Prism::StringNode
                @partial = assoc_val.unescaped
              else
                @unsupported = :undeterminable_template
                return
              end
            when "layout"
              if @partial
                @unsupported = :layout_and_partial
                return
              end

              assoc_value = assoc.value

              case assoc_value
              when Prism::StringNode

                @partial = assoc_value.unescaped
              when Prism::SymbolNode
                @partial = assoc_value.slice
              else
                @unsupported = :undeterminable_layout
                return
              end

            when "locals"
              if assoc.value.is_a?(Prism::CallNode) || assoc.value.is_a?(Prism::LocalVariableReadNode)
                @unsupported = :undterminable_locals
                return
              end

              extract_locals(assoc.value)
            else
              @unsupported = :extra_key
              return
            end
          end
        else
          @unsupported = :unsupported_first_arg_type
        end
      end

      def visit_block_node(node)
        method_name = @template_resolver.template_method(@partial, @locals)
        return unless method_name
        method_call = "#{method_name}(#{@locals_source}, @output_buffer)"

        if node.body.body.size != 1 || !node.body.body.first.is_a?(Prism::MissingNode)
          @unsupported = :block_content
          return
        end

        push "lambda { |&block| #{method_call} { |*args| block.call(*args); nil } }.call #{node.opening_loc.slice}"
      end

      def visit_block_argument_node(node)
        method_name = @template_resolver.template_method(@partial, @locals)
        return unless method_name
        method_call = "#{method_name}(#{@locals_source}, @output_buffer)"

        push "#{method_call} { |*args| #{node.expression.name}.call(*args); nil }"
      end

      private

      def push(str)
        @buffer << str
      end

      def extract_locals(node)
        @locals = node.elements.map { _1.key.unescaped.to_sym }

        if node.is_a?(Prism::HashNode)
          @locals_source = node.slice
        else
          @locals_source = "{ #{node.slice} }"
        end
      end
    end

    def rewrite(code)
      rewriter = RenderRewriter.new(template_resolver)
      Prism.parse(code).value.accept(rewriter)
    end

    VIEW_COMPONENT_REGEX = /render[\n( ]+(?:::)?[A-Z]/

    def add_expression(indicator, code)
      if code.strip.start_with?(/render[( ]/) && indicator == "=" && !code.match?(VIEW_COMPONENT_REGEX) && (rewrite = rewrite(code)) && rewrite != ""
        add_code(rewrite)
      else
        super(indicator, code)
      end
    end
  end
end
