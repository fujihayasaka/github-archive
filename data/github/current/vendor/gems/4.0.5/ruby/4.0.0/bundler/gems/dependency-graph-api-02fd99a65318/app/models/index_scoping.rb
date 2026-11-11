module IndexScoping
  def ignore_index(index)
     # This is how Active Record quotes index names in database migrations.
    quoted_index_name = connection.quote_column_name(index)
    from("#{quoted_table_name} IGNORE INDEX(#{quoted_index_name})")
  end

  def use_index(index)
     # This is how Active Record quotes index names in database migrations.
    quoted_index_name = connection.quote_column_name(index)
    from("#{quoted_table_name} USE INDEX(#{quoted_index_name})")
  end
end
