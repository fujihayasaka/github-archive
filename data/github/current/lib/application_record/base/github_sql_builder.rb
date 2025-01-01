# typed: true
# frozen_string_literal: true

# Internal: Proxy class for `GitHub::SQL` ensuring the same connection is used.
#
# Instances of this class quack like the `GitHub::SQL` class.
#
# As an example, instead of using `GitHub::SQL` directly, we use `.github_sql`:
#
#     Repository.github_sql.value "SELECT `id` FROM `repositories` LIMIT 1"
#
#     sql = Repository.github_sql.new("...", { user_id: 5 })
#     sql.add("...", { ids: [1, 2, 3] })
#     results = sql.run
#
class GitHubSQLBuilder
  attr_reader :connection, :default_options

  def initialize(connection, default_options)
    @connection = connection
    @default_options = default_options.freeze
  end

  def new(sql = nil, bindings = {})
    if sql.is_a?(Hash)
      bindings = sql
      sql = nil
    end

    adjusted_bindings = bindings.reverse_merge(default_options).merge(connection: connection)
    GitHub::SQL.new(sql, adjusted_bindings) #rubocop:disable GitHub/DoNotCallMethodsOnGitHubSQL
  end

  def run(sql, bindings = {})
    new(sql, bindings).run
  end

  def results(sql, bindings = {})
    new(sql, bindings).results
  end

  def hash_results(sql, bindings = {})
    new(sql, bindings).hash_results
  end

  def values(sql, bindings = {})
    new(sql, bindings).values
  end

  def value(sql, bindings = {})
    new(sql, bindings).value
  end

  def transaction(options = {}, &block)
    connection.transaction(**options, &block)
  end
end
