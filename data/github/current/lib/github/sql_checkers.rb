# typed: true
# frozen_string_literal: true

module GitHub::SQLCheckers
  autoload :TableSharding, "github/sql_checkers/table_sharding"
  autoload :TableParser, "github/sql_checkers/table_parser"
  autoload :SchemaDomain,  "github/sql_checkers/schema_domain"
  autoload :Authorization, "github/sql_checkers/authorization"
  autoload :TenantNamespacing, "github/sql_checkers/tenant_namespacing"
  autoload :DomainIsolation, "github/sql_checkers/domain_isolation"
end
