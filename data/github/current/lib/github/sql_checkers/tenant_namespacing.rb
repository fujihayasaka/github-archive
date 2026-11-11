# typed: true
# frozen_string_literal: true

module GitHub::SQLCheckers::TenantNamespacing
  class UnsafeDisplayLoginQueryError < Exception; end
end

require "github/sql_checkers/stacktrace_parser"
require "github/sql_checkers/statement_checker"
require "github/sql_checkers/tenant_namespacing/statement_checker"
