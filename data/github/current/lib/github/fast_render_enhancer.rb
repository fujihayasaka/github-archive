# typed: true
# frozen_string_literal: true

require "parser/current"
require "action_view"

module GitHub
  module FastRenderEnhancer
    extend T::Helpers
    extend T::Sig
    include Kernel
    abstract!

    sig { abstract.params(code: String).void }
    def add_code(code); end

    def self.cache
      @cache ||= Hash.new
    end

    if !ActionView::Resolver.caching?
      ActiveSupport::Reloader.to_prepare do
        GitHub::FastRenderEnhancer.cache.clear
      end
    end

    BLOCK_EXPR = /\s*((\s+|\))do|\{)(\s*\|[^|]*\|)?\s*\Z/

    class RenderParser
      def initialize(src)
        @src = src
      end

      def parse
        src = @src.gsub(BLOCK_EXPR, " ") # Remove block expression leftovers
        Parser::CurrentRuby.parse(src)
      rescue Parser::SyntaxError
        raise "Failed to parse ERB expression:\n\n#{@src}"
      end

      def arguments
        extract_render_arguments
      end

      def extract_render_arguments
        expr_node = parse

        expr_node = expr_node.children[1] || expr_node.children[2] if expr_node.type == :if

        receiver, method, *args = expr_node.children
        return if receiver || method != :render || args.size < 1 || args.size > 2

        string_or_options, locals_or_block = args

        result = on_render(string_or_options, locals_or_block)
        return unless result

        result[:begin] = expr_node.location.expression.begin_pos
        result[:end] = expr_node.location.expression.end_pos
        result
      end

      def continuing_block?
        BLOCK_EXPR =~ @src
      end

      def on_render(string_or_options = nil, locals_or_block = nil)
        case string_or_options && string_or_options.type
        when :str
          on_render_partial_str(string_or_options, locals_or_block)
        when :hash
          on_render_partial_hash(string_or_options, locals_or_block)
        end
      end

      def on_render_partial_str(partial, locals = nil)
        build_partial_result(partial_exp: partial, locals_exp: locals)
      end

      def on_render_partial_hash(options, block_exp = nil)
        pairs = options.children

        # Deoptimize if we encounter an unsupported option
        return if pairs.any? { |pair| ![:partial, :locals, :layout].include?(sym(pair_key(pair))) }

        partial_pair = pairs.find { |pair| sym(pair_key(pair)) == :partial }
        layout_pair = pairs.find { |pair| sym(pair_key(pair)) == :layout }
        locals_pair = pairs.find { |pair| sym(pair_key(pair)) == :locals }

        # Need at least a partial or a layout
        return if !partial_pair && !layout_pair

        # Can't handle combination of partial with layout (yet)
        return if partial_pair && layout_pair

        # If block_exp isn't a block_pass, this is probably invalid
        return if block_exp && block_exp.type != :block_pass

        # Only :layout key should be used with a block
        if partial_pair && (block_exp || continuing_block?)
          return
        end

        build_partial_result(
          partial_exp: pair_value(partial_pair || layout_pair),
          locals_exp: locals_pair && pair_value(locals_pair),
          block_exp: block_exp,
        )
      end

      def build_partial_result(partial_exp:, locals_exp: nil, block_exp: nil)
        return if locals_exp && locals_exp.type != :hash

        partial_path = str(partial_exp)
        return unless partial_path

        result = { partial: partial_path }

        if locals_exp
          locals = locals_exp.children.map { |pair| sym(pair_key(pair)) }

          src = locals_exp.loc.expression.source
          src = "{ #{src} }" unless src.strip.start_with?("{")

          result.merge!(locals: locals, locals_source: src)
        else
          result.merge!(locals: [], locals_source: "{}")
        end

        if block_exp && block_exp.type == :block_pass
          result[:block_source] = block_exp.loc.expression.source
        end

        result
      end

      def pair_key(node)
        node.children[0] if node.type == :pair
      end

      def pair_value(node)
        node.children[1] if node.type == :pair
      end

      def sym(node)
        node.children[0] if node.type == :sym
      end

      def str(node)
        node.children[0] if node.type == :str
      end
    end

    def find_partial(path, locals, controller)
      # Hold reference to ActionView::Template to avoid finalizer undefining compiled method.
      # If we have a single template then we can optimize rendering it. Otherwise
      # leave the code unchanged to let Rails handle the rendering.
      FastRenderEnhancer.cache[[path, locals]] ||= begin
        templates = controller.lookup_context.find_all(path, [], true, locals, {})
        if templates.size == 1
          templates[0]
        else
          nil
        end
      end
    end

    def determine_template(path, locals)
      controller = T.unsafe(ApplicationController).new
      template = find_partial(path, locals, controller)
      return nil unless template
      unless template.instance_variable_get(:@compile_mutex).locked?
        template.send(:compile!, controller.view_context)
      end
      template
    end

    def rewrite(code, method_name, args)
      buf = Parser::Source::Buffer.new("(erb)")
      buf.source = code

      rewriter = Parser::Source::TreeRewriter.new(buf)
      range = Parser::Source::Range.new(buf, args[:begin], args[:end])

      if code =~ BLOCK_EXPR
        rewriter.replace(range, "lambda { |&block| #{method_name}(#{args[:locals_source]}, @output_buffer) { |*args| block.call(*args); nil } }.call").process
      elsif args[:block_source]
        rewriter.replace(range, "#{method_name}(#{args[:locals_source]}, @output_buffer) { |*args| #{args[:block_source][1..-1]}.call(*args); nil }").process
      else
        rewriter.replace(range, "#{method_name}(#{args[:locals_source]}, @output_buffer)").process
      end
    end

    def extract_render_arguments(code)
      GitHub::FastRenderEnhancer::RenderParser.new(code).arguments
    end

    # A regex to filter out most ViewCompoents from the render, as they cannot
    # be optimized. This avoids us spending time parsing their Ruby code.
    VIEW_COMPONENT_REGEX = /render[( ]+[A-Z]/

    def try_rewrite_expression(indicator, code)
      if code.strip.start_with?("render") && indicator == "=" && !code.match?(VIEW_COMPONENT_REGEX)
        if (args = extract_render_arguments(code))
          begin
            template = determine_template(args[:partial], args[:locals])
            return if template.nil? || template.strict_locals?
            method_name = template.send(:method_name)
          rescue ActionView::MissingTemplate
            raise "Could not resolve partial: #{args[:partial].inspect}\n\n#{code}"
          end

          rewrite(code, method_name, args) if method_name
        end
      end
    end

    def add_expression(indicator, code)
      if rewrite = try_rewrite_expression(indicator, code)
        add_code(rewrite)
      else
        super(indicator, code)
      end
    end
  end
end
