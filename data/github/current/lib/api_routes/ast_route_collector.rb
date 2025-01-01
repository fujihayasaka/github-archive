# typed: true
# frozen_string_literal: true

# ASTRouteCollector uses static analyses to extract information about routes.
class ApiRoutes::ASTRouteCollector < Parser::AST::Processor
  def self.for(namespace)
    collector = new(namespace)

    paths = ["#{Rails.root}/app/#{namespace.underscore}.rb"]

    glob  = File.join(Rails.root, "app", namespace.underscore, "**", "*_dependency.rb")

    paths += Dir[glob]

    paths.each do |path|
      collector.file_path = path.gsub(Rails.root.to_s, "")

      buffer = Parser::Source::Buffer.new(namespace)
      buffer.source = File.read(path)

      builder   = RuboCop::AST::Builder.new
      parser    = Parser::CurrentRuby.new(builder)
      root_node = parser.parse(buffer)

      collector.process(root_node)
    end

    collector
  end

  def self.endpoints_in(namespace)
    self.for(namespace.to_s).endpoints
  end

  attr_reader :namespace
  attr_accessor :file_path
  def initialize(namespace)
    @namespace = namespace
    @endpoints_by_route = {}
  end

  def endpoints
    @endpoints_by_route.values
  end

  def lookup(route)
    @endpoints_by_route[route]
  end

  VERBS = [:head, :get, :post, :delete, :patch, :put]
  METHOD_NAMES = VERBS + [:verbs]

  def api_nodes(node)
    return [] unless node.block_type?

    defn, _, body = node.children

    return [] unless defn.send_type? && METHOD_NAMES.include?(defn.method_name)
    return [] if defn.arguments.empty?

    patterns = defn.arguments.reject { |arg| arg.sym_type? || arg.hash_type? }
    return [] if patterns.empty?
    return [] unless patterns.all? { |pattern| pattern.str_type? || pattern.regexp_type? }

    pattern = patterns.last
    route = pattern.children.first
    if pattern.regexp_type?
      route = route.children.first
    end

    routes = patterns.map do |pattern|
      pattern.regexp_type? ? pattern.children.first.children.first : pattern.children.first
    end

    if VERBS.include?(node.method_name)
      return routes.map { |route| ApiRoutes::ASTEndpoint.from(namespace, node.method_name, route, body, file_path, node) }
    end

    return [] if node.method_name != :verbs
    defn.arguments.select(&:sym_type?).map do |arg|
      routes.map { |route| ApiRoutes::ASTEndpoint.from(namespace, arg.children.first, route, body, file_path, node) }
    end.flatten
  end

  def on_block(node)
    endpoints = api_nodes(node)
    endpoints.each do |endpoint|
      @endpoints_by_route[endpoint.to_s] = endpoint
    end

    if endpoints.empty?
      node.updated(nil, process_all(node))
    end
  end
end
