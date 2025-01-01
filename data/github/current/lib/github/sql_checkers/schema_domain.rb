# typed: true
# frozen_string_literal: true

# See https://thehub.github.com/engineering/development-and-ops/dotcom/schema-domains/.

require "yaml"

module GitHub::SQLCheckers::SchemaDomain
  # These are only raised in dev and should always blow through
  # catchall rescues, hence the inheritence from Exception.
  class CrossDomainQueryError < Exception; end
  class CrossDomainTransactionError < Exception; end

  PATH = GitHub::AppEnvironment.root.join("db", "schema-domains.yml").to_s.freeze
  DOMAINS = YAML.load_file(PATH).tap do |hash|
    hash.values.each do |tables|
      tables.freeze
      tables.each(&:freeze)
    end
  end.freeze

  def self.domains
    DOMAINS.keys
  end

  def self.same?(tables)
    return true if tables.empty? || tables.size == 1

    first_domain = self.for(tables.first)
    tables.all? { |t| first_domain == self.for(t) }
  end

  def self.for(table)
    by_tables[table]
  end

  def self.by_tables
    return @domains_by_tables if defined?(@domains_by_tables)

    @domains_by_tables = DOMAINS.each_with_object({}) do |(domain, tables), result|
      tables.each { |t| result[t] = domain }
    end
  end

  def self.tables(except: [])
    DOMAINS.except(*except).values.flatten
  end

  def self.allowing_cross_domain_queries(&block)
    ActiveSupport::ExecutionContext.set("cross-schema-domain-query-exempted": true, &block)
  end

  def self.allowing_cross_domain_transactions(&block)
    ActiveSupport::ExecutionContext.set("cross-schema-domain-transaction-exempted": true, &block)
  end
end

require "github/sql_checkers/schema_domain/statement_checker"
