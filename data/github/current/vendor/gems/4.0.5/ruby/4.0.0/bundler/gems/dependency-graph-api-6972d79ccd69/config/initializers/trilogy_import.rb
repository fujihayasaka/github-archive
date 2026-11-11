require "activerecord-import/adapters/mysql_adapter"

module QueryRetries
  # Should match upstream except for `allow_retry`
  # https://github.com/rails/rails/blob/b4d8603bd3a9f814e0a233ee39b1cdcee2e60e29/activerecord/lib/active_record/connection_adapters/trilogy/database_statements.rb#L44
  def raw_execute(*args, **kwargs)
    super(*args, **kwargs.merge(allow_retry: true))
  end
end

module ActiveRecord
  module ConnectionAdapters
    class TrilogyAdapter
      include ActiveRecord::Import::MysqlAdapter
      prepend QueryRetries
    end
  end
end
