# typed: true
# frozen_string_literal: true

require "parser/current"

class ApiRoutes::ASTAccessDefinitionCollector < Parser::AST::Processor
  SendNodeType = T.type_alias { RuboCop::AST::SendNode }

  def self.for(paths)
    collector = new
    paths.each do |path|
      ast = parse(File.read(path), label: path)
      collector.process(ast)
    end
    collector
  end

  def self.parse(source, label:)
    buffer        = Parser::Source::Buffer.new(label)
    buffer.source = source
    builder       = RuboCop::AST::Builder.new
    parser        = Parser::CurrentRuby.new(builder)

    parser.parse(buffer)
  end

  attr_reader :access_definitions
  def access_definition_nodes(root)
    return [] unless root.is_a?(RuboCop::AST::Node)

    child = root.children.first

    if child && child.is_a?(RuboCop::AST::Node) && child.send_type? && T.cast(child, SendNodeType).method_name == :define_access
      child = T.cast(child, SendNodeType)
      nodes = T.let([], T::Array[ApiRoutes::EgressAccessDefinition])
      names = child.arguments.map { |arg| arg.children.first }

      names.each do |name|
        nodes << ApiRoutes::EgressAccessDefinition.new(name, roles_in(root))
      end
      return nodes
    end

    nodes = T.let([], T::Array[RuboCop::AST::Node])
    root.children.each do |child|
      nodes += access_definition_nodes(child)
    end
    nodes
  end

  def roles_in(root)
    return [] unless root.is_a?(RuboCop::AST::Node)

    # Special case for releases.
    # Draft releases are only available if you have write access to the repo.
    # We don't care about that here, so we're working extra hard to bail out
    # early if we talk about publishing.
    published = root.child_nodes.find do |child|
      child.child_nodes.find do |grandchild|
        if grandchild.send_type? && grandchild.method_name == :allow
          node = child.child_nodes.last
          node.send_type? && node.method_name == :published?
        end
      end
    end
    if !!published
      node = published.child_nodes.find { |node| node.send_type? && node.method_name == :allow }
      return [node.arguments.first.children.first]
    end

    # Get rid of any allow blocks that are explicitly not for actors with granular permissions.
    nodes = root.child_nodes.reject do |child|
      if child.block_type?
        grandchild = child.child_nodes.first
        grandchild && grandchild.send_type? && grandchild.method_name == :allow && !!user_only(child).first
      end
    end

    roles = T.let([], T::Array[RuboCop::AST::Node])
    nodes.each do |child|
      if child.send_type? && child.method_name == :allow
        roles << child.arguments.first.children.first
      else
        roles += roles_in(child)
      end
    end
    roles
  end

  def user_only(root)
    return [] unless root.is_a?(RuboCop::AST::Node)

    if root.send_type? && T.cast(root, SendNodeType).method_name == :! && root.receiver.send_type? && root.receiver.method_name == :can_have_granular_permissions?
      return [true]
    end

    results = T.let([], T::Array[RuboCop::AST::Node])
    root.child_nodes.each do |child|
      results += user_only(child)
    end
    results
  end

  def on_block(node)
    @access_definitions ||= []

    @access_definitions += access_definition_nodes(node)
    if @access_definitions.empty?
      node.updated(nil, process_all(node))
    end
  end
end
