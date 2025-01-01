module DependencyGraph
  module Connection
    # Set the database isolation level to READ COMMITTED on the connection for a
    # database role for the duration of the passed block.
    #
    # https://dev.mysql.com/doc/refman/5.7/en/innodb-transaction-isolation-levels.html
    def with_read_committed(role:)
      connection = ActiveRecord::Base.connected_to(role: role) { ActiveRecord::Base.connection }
      connection.execute("set session transaction isolation level read committed")
      begin
        yield
      ensure
        connection.execute("set session transaction isolation level repeatable read")
      end
    end

    module_function :with_read_committed
  end
end
