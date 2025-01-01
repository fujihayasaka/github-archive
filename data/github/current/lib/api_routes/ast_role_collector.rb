# typed: true
# frozen_string_literal: true

class ApiRoutes::ASTRoleCollector < Parser::AST::Processor
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

  attr_reader :roles
  def role_nodes(root)
    return [] unless root.is_a?(RuboCop::AST::Node)

    child = root.children.first
    if child && child.is_a?(RuboCop::AST::Node) && child.send_type? && T.cast(child, SendNodeType).method_name == :role
      child = T.cast(child, SendNodeType)
      nodes = T.let([], T::Array[ApiRoutes::EgressRole])
      names = child.arguments.map { |arg| arg.children.first }
      names.each do |name|
        nodes << ApiRoutes::EgressRole.new(name, permissions(root))
      end
      return nodes
    end

    nodes = T.let([], T::Array[RuboCop::AST::Node])
    root.children.each do |child|
      nodes += role_nodes(child)
    end
    nodes
  end

  def permissions(root)
    return {} unless root.is_a?(RuboCop::AST::Node)

    perms = T.let({}, T::Hash[String, Symbol])
    root.children.each do |child|
      next unless child.is_a?(RuboCop::AST::Node)

      unless child.send_type?
        perms = perms.merge permissions(child)
        next
      end
      next if child.receiver.nil?

      child = T.cast(child, SendNodeType)
      if child.method_name == :== && (child.receiver.send_type? && child.receiver.method_name == :[])
        child.children.each do |node|
          next unless node.is_a?(RuboCop::AST::Node)

          if node.send_type? && node.receiver.send_type? && node.receiver.method_name == :permissions && T.cast(node, SendNodeType).method_name == :[]
            name = child.receiver.arguments.last.children.first
            level = child.arguments.last.children.first
            perms = perms.merge name => level
          end
        end
      elsif child.method_name == :readable_by?
        child.children.each do |node|
          next unless node.is_a?(RuboCop::AST::Node)

          if node.receiver && node.receiver.send_type? && node.receiver.method_name == :resources
            node = T.cast(node, SendNodeType)
            name = node.method_name.to_s
            name = "single file" if name == "file"
            perms = perms.merge name => :read
          elsif child.receiver.children.first == :project
            perms = perms.merge "repository_projects" => :read, "organization_projects" => :read
          end
        end
      elsif child.method_name == :writable_by?
        child.children.each do |node|
          next unless node.is_a?(RuboCop::AST::Node)

          if node.receiver && node.receiver.send_type? && node.receiver.method_name == :resources
            node = T.cast(node, SendNodeType)
            name = node.method_name.to_s
            name = "single file" if name == "file"
            perms = perms.merge name => :write
          elsif child.receiver.children.first == :project
            perms = perms.merge "repository_projects" => :write, "organization_projects" => :write
          end
        end
      elsif child.method_name == :lockable_by?
        perms = perms.merge "issues" => :write, "pull_requests" => :write
      elsif child.method_name == :can_create_repository? && child.receiver.children.last == :org
        perms = perms.merge "administration" => :write
      elsif child.method_name == :projects_readable_by?
        perms = perms.merge "repository_projects" => :read, "organization_projects" => :read
      elsif child.method_name == :projects_writable_by?
        perms = perms.merge "repository_projects" => :write, "organization_projects" => :write
      end
    end

    perms
  end

  def on_block(node)
    @roles ||= []

    @roles += role_nodes(node)
    if @roles.empty?
      node.updated(nil, process_all(node))
    end
  end

  def on_send(node)
    if node.method_name == :role && node.arguments.first.children.first == :everyone
      @roles ||= []
      @roles << ApiRoutes::EgressRole.new(:everyone, { "metadata" => :read })
    end
  end
end
