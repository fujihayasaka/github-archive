# typed: true
# frozen_string_literal: true

# ASTPermissionCollector uses static analysis to get information about route authz.
class ApiRoutes::ASTPermissionCollector < Parser::AST::Processor
  def self.endpoints_in(namespace)
    self.for(namespace).endpoints
  end

  def self.for(namespace)
    collection = ApiRoutes::ASTRouteCollector.for(namespace.to_s)
    egress_collection.process(collection)
  end

  def self.egress_collection
    return @egress_collection if @egress_collection

    dir = File.absolute_path("../../../config/access_control", __FILE__)
    files = Dir.glob(File.join(dir, "**", "*.rb"))
    role_files, access_files = files.partition { |file| file.end_with?("roles.rb") }

    roles = ApiRoutes::ASTRoleCollector.for(role_files).roles
    access_definitions = ApiRoutes::ASTAccessDefinitionCollector.for(access_files).access_definitions

    @egress_collection = ApiRoutes::EgressCollection.new(access_definitions: access_definitions, roles: roles)
  end
end
