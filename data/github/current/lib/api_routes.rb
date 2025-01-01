# typed: true
# frozen_string_literal: true

module ApiRoutes
  autoload :ASTAccessDefinitionCollector, "api_routes/ast_access_definition_collector"
  autoload :ASTEndpoint, "api_routes/ast_endpoint"
  autoload :ASTPermissionCollector, "api_routes/ast_permission_collector"
  autoload :ASTRoleCollector, "api_routes/ast_role_collector"
  autoload :ASTRouteCollector, "api_routes/ast_route_collector"
  autoload :AuditFormatter, "api_routes/audit_formatter"
  autoload :AuditReport, "api_routes/audit_report"
  autoload :Collection, "api_routes/collection"
  autoload :ControlAccessCall, "api_routes/control_access_call"
  autoload :DefaultCollector, "api_routes/default_collector"
  autoload :DefaultEndpoint, "api_routes/default_endpoint"
  autoload :DefaultReport, "api_routes/default_report"
  autoload :EgressAccessDefinition, "api_routes/egress_access_definition"
  autoload :EgressCollection, "api_routes/egress_collection"
  autoload :EgressRole, "api_routes/egress_role"
  autoload :GranularPermissionsReport, "api_routes/granular_permissions_report"
  autoload :MissingDocumentationUrlsReport, "api_routes/missing_documentation_urls_report"
  autoload :Namespaces, "api_routes/namespaces"
  autoload :OwnershipReport, "api_routes/ownership_report"
  autoload :StatisticsReport, "api_routes/statistics_report"
  autoload :UserToServerReport, "api_routes/user_to_server_report"
  autoload :WipPrReport, "api_routes/wip_pr_report"
end
