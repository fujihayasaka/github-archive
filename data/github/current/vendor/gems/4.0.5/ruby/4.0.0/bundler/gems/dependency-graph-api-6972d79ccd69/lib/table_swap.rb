class TableSwap
  def initialize(table_name)
    @table_name = table_name
  end

  def with_swap
    generate_tmp_table
    yield(tmp_table_name)
    swap
  end

  private

  attr_reader :table_name

  def tmp_table_name
    @tmp_table_name ||= "#{table_name}_tmp"
  end

  def generate_tmp_table
    connection.execute("DROP TABLE IF EXISTS #{tmp_table_name}")
    connection.execute("CREATE TABLE #{tmp_table_name} LIKE #{table_name}")
  end

  def swap
    connection.execute("RENAME TABLE #{table_name} to #{table_name}_bak")
    connection.execute("RENAME TABLE #{tmp_table_name} to #{table_name}")
    connection.execute("DROP TABLE #{table_name}_bak")
  end

  def connection
    ActiveRecord::Base.connection
  end
end
