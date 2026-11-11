# typed: true
# frozen_string_literal: true

# rubocop:disable GitHub/DoNotCallMethodsOnActiveRecordBase
# rubocop:disable GitHub/DoNotCallMethodsOnGitHubSQL

module VTCombo
  def self.dump_vschema(db)
    config = ActiveRecord::Base.configurations.configs_for(env_name: Rails.env, name: db).configuration_hash

    if config[:vitess] && config[:vschema_path]
      vschema = VTCombo.get_vschema(config[:database])

      original_db_config = ActiveRecord::Base.connection_db_config
      ActiveRecord::Base.establish_connection(config)

      begin
        if vschema["sharded"].nil? || vschema["sharded"] == false
          puts "Skipping table augmentations for vschema #{config[:vschema_path]}"
          augmented_vschema = vschema
        else
          augmented_vschema = {}
          augmented_vschema["sharded"] = vschema["sharded"] unless vschema["sharded"].nil?
          augmented_vschema["vindexes"] = vschema["vindexes"] unless vschema["vindexes"].nil?
          augmented_vschema["tables"] = {}

          ActiveRecord::Base.connection.tables.each do |table_name|
            columns = ActiveRecord::Base.connection.columns(table_name)

            augmented_table = {}

            if vschema["tables"] && vschema["tables"][table_name]
              if vschema["tables"][table_name]["autoIncrement"]
                augmented_table["autoIncrement"] = vschema["tables"][table_name]["autoIncrement"]
                augmented_table["autoIncrement"]["sequence"].sub!(/\A\w+\./, "")
              end

              if vschema["tables"][table_name]["columnVindexes"]
                augmented_table["columnVindexes"] = vschema["tables"][table_name]["columnVindexes"]
              end

              if vschema["tables"][table_name]["type"]
                augmented_table["type"] = vschema["tables"][table_name]["type"]
              end
            end

            augmented_table["columns"] = columns.map do |c|
              vschema_type = case c.sql_type
              when /\Avarchar\(\d+\)\z/
                "VARCHAR"
              when /\Achar\(\d+\)\z/
                "CHAR"
              when "date"
                "DATE"
              when /\Adatetime(\(\d+\))?\z/
                "DATETIME"
              when /\Avarbinary\(\d+\)\z/
                "VARBINARY"
              when /\Abinary\(\d+\)\z/
                "BINARY"
              when /\Abigint(\(\d+\))? unsigned\z/
                "UINT64"
              when /\Abigint(\(\d+\))?\z/
                "INT64"
              when /\Aint(\(\d+\))?\z/
                "INT32"
              when /\Aint(\(\d+\))? unsigned\z/
                "UINT32"
              when /\Amediumint(\(\d+\))?\z/
                "INT24"
              when /\Amediumint(\(\d+\))? unsigned\z/
                "UINT24"
              when /\Asmallint(\(\d+\))?\z/
                "INT16"
              when /\Asmallint(\(\d+\))? unsigned\z/
                "UINT16"
              when /\Atinyint(\(\d+\))?\z/
                "INT8"
              when /\Atinyint(\(\d+\))? unsigned\z/
                "UINT8"
              when /\Aenum\(.*?\)\z/
                "ENUM"
              when "timestamp"
                "TIMESTAMP"
              when "float"
                "FLOAT32"
              when "text", "longtext", "mediumtext"
                "TEXT"
              when "blob", "mediumblob"
                "BLOB"
              when "json"
                "JSON"
              else
                raise RuntimeError.new("unknown column sql type '#{c.sql_type}'")
              end

              { "name" => c.name, "type" => vschema_type }
            end
            augmented_table["columnListAuthoritative"] = true

            augmented_vschema["tables"][table_name] = augmented_table
          end
        end

        vschema_path = Rails.root.join(config[:vschema_path])

        File.open(vschema_path, "w") do |f|
          f.write(JSON.pretty_generate(augmented_vschema))
          f.write("\n")
        end
      ensure
        ActiveRecord::Base.establish_connection(original_db_config) if original_db_config
      end
    end
  end

  def self.drop_sequence(sequence_name)
    db_config = ActiveRecord::Base.configurations.configs_for(env_name: Rails.env, name: "vt_primary")
    keyspace = db_config.configuration_hash[:database]

    vschema = get_vschema(keyspace)
    vschema["tables"].delete(sequence_name.to_s)

    vschema_path = Rails.root.join("tmp", "vtcombo", db_config.configuration_hash[:database], "tmp_vschema.json")
    File.open(vschema_path, "w") do |f|
      f.write(::JSON.pretty_generate(vschema))
      f.write("\n")
    end

    apply_vschema_file(db_config, keyspace, vschema_path)

    File.delete(vschema_path)
  end

  def self.drop_auto_increment(db_config, table_name, column_name, sequence_name)
    keyspace = db_config.configuration_hash[:database]

    vschema = get_vschema(keyspace)
    vschema.dig("tables", table_name)&.delete_if do |key, value|
      key == "autoIncrement" && value["column"] == column_name && value["sequence"] == sequence_name
    end

    vschema_path = Rails.root.join("tmp", "vtcombo", db_config.configuration_hash[:database], "tmp_vschema.json")
    File.open(vschema_path, "w") do |f|
      f.write(::JSON.pretty_generate(vschema))
      f.write("\n")
    end

    apply_vschema_file(db_config, keyspace, vschema_path)

    File.delete(vschema_path)
  end

  def self.apply_vschema_file(db_config, keyspace, vschema_path)
    vtctl = Progeny::Command.new(Rails.root.join("vendor", "vitess", "current", "bin", "vtctlclient").to_s, "--server", "localhost:15001", "ApplyVSchema", "--", "--vschema_file", vschema_path.to_s, keyspace)

    unless vtctl.status.success?
      puts vtctl.err
      raise "Could not apply vschema"
    end

    # Vitess applies the VSchema asynchronously. This is a bit complicated and the end goal is to fix this in Vitess.
    # However, for now, a compromise is to query the vindexes and see if _any_ vindex is created for the keyspace.
    # This only applies if the keyspace is sharded.
    vtctl = Progeny::Command.new(Rails.root.join("vendor", "vitess", "current", "bin", "vtctlclient").to_s, "--server", "localhost:15001", "FindAllShardsInKeyspace", "--", keyspace)

    unless vtctl.status.success?
      puts vtctl.err
      raise "Could not get shards for keyspace '#{keyspace}'"
    end

    keyspace_shards = JSON.parse(vtctl.out).keys.count

    if keyspace_shards > 1
      should_reconnect = ActiveRecord::Base.connection_pool.active_connection?

      end_time = Time.now + 30.seconds
      any_vindex_created = T.let(false, T::Boolean)

      begin
        ActiveRecord::Base.establish_connection(db_config)

        while Time.now < end_time do
          res = ActiveRecord::Base.connection.execute("show vschema vindexes")

          keyspaces_with_vindexes = res&.rows.compact.map(&:first).uniq

          any_vindex_created = keyspaces_with_vindexes.include? keyspace
          break if any_vindex_created

          sleep 0.5
        end
      ensure
        ActiveRecord::Base.establish_connection(ActiveRecord::Tasks::DatabaseTasks.env.to_sym) if should_reconnect
      end

      raise "Could not apply vschema" unless any_vindex_created
    end
  end

  def self.reload_schema_for_keyspace(keyspace)
    vtctl = Progeny::Command.new(Rails.root.join("vendor", "vitess", "current", "bin", "vtctlclient").to_s, "--server", "localhost:15001", "ReloadSchemaKeyspace", "--", "--include_primary=true", keyspace)

    unless vtctl.status.success?
      puts vtctl.err
      raise "Could not reload schema for keyspace #{keyspace}"
    end
  end

  def self.get_vschema(keyspace)
    vtctl = Progeny::Command.new(Rails.root.join("vendor", "vitess", "current", "bin", "vtctlclient").to_s, "--server", "localhost:15001", "GetVSchema", "--", keyspace)

    unless vtctl.status.success?
      puts vtctl.err
      raise "Could not get vschema for keyspace '#{keyspace}'"
    end

    JSON.parse(vtctl.out)
  end

  def self.load_vschema_file(db_config, sequence_keyspace_name:)
    return unless db_config.configuration_hash[:vschema_path]

    puts "Generating local vschema from #{db_config.configuration_hash[:vschema_path]}"
    vschema_path = Rails.root.join(db_config.configuration_hash[:vschema_path])

    vschema = JSON.load(vschema_path)
    if vschema["tables"]
      vschema["tables"].each do |table_name, data|
        if data["autoIncrement"] && data["autoIncrement"]["sequence"]
          vschema["tables"][table_name]["autoIncrement"]["sequence"] = "#{sequence_keyspace_name}.#{data["autoIncrement"]["sequence"]}"
        end
      end
    end

    FileUtils.mkdir_p(Rails.root.join("tmp", "vtcombo", db_config.configuration_hash[:database]))
    File.write(Rails.root.join("tmp", "vtcombo", db_config.configuration_hash[:database], "vschema.json"), JSON.pretty_generate(vschema))

    if db_config.configuration_hash[:vitess]
      puts "Applying vschema to #{vschema_path} #{db_config.configuration_hash[:database]}"
      vschema_path = Rails.root.join("tmp", "vtcombo", db_config.configuration_hash[:database], "vschema.json")
      VTCombo.apply_vschema_file(db_config, db_config.configuration_hash[:database], vschema_path)
    end
  end

  def self.initialize_sequences(db_config)
    should_reconnect = ActiveRecord::Base.connection_pool.active_connection?

    config_hash = db_config.configuration_hash

    VTCombo.reload_schema_for_keyspace(config_hash[:database]) if config_hash[:vitess]

    ActiveRecord::Base.establish_connection(db_config)

    sql = GitHub::SQL.new(<<-SQL, database: config_hash[:database])
      SELECT table_name FROM information_schema.tables WHERE table_schema = :database AND table_comment = "vitess_sequence";
    SQL

    tables = ActiveRecord::Base.connection.select_values(sql.query)

    if tables.any?
      puts "Inserting sequences in db #{config_hash[:database]} for tables: #{tables.join(",")}"
    else
      puts "Found no sequence tables in #{config_hash[:database]}."
    end

    tables.each do |table|
      sql = GitHub::SQL.new(<<-SQL, table: GitHub::SQL.LITERAL(table))
        INSERT IGNORE INTO :table (id, next_id, cache) VALUES (0,1,1)
      SQL

      ActiveRecord::Base.connection.insert(sql.query)
    end
  ensure
    if should_reconnect
      ActiveRecord::Base.establish_connection(ActiveRecord::Tasks::DatabaseTasks.env.to_sym)
    end
  end
end
