# typed: false # rubocop:todo Sorbet/TrueSigil
# frozen_string_literal: true

module GitHub
  module VitessMigrationExtensions
    # Adds a vindex to `table_name` on `column_name` using the vindex named `vindex_name`, or fails if that vindex does not exist yet
    #
    # Add the `hash` vindex` to the `repository_id` column on `workflow_job_runs`
    #
    #   add_vindex :workflow_job_runs, :hash, :repository_id
    #
    def add_vindex(table_name, vindex_name, column_name)
      return unless vitess_enabled?

      reversible do |dir|
        dir.up do
          column_name = Array(column_name).map { |col| quote_column_name(col) }

          execute <<~SQL
            ALTER VSCHEMA ON #{quote_table_name(table_name)} ADD VINDEX #{quote_table_name(vindex_name)} (#{column_name.join(', ')})
          SQL
        end

        dir.down do
          remove_vindex(table_name, vindex_name, column_name)
        end
      end
    end

    def create_vindex(vindex_name, type, params)
      return unless vitess_enabled?

      reversible do |dir|
        dir.up do
          params = params.map { |key, value| [quote_table_name(key), quote_table_name(value)].join(" = ") }.join(", ")

          execute <<~SQL
            ALTER VSCHEMA CREATE VINDEX #{quote_table_name(vindex_name)} using #{quote_table_name(type)} WITH #{params}
          SQL
        end

        dir.down do
          drop_vindex(vindex_name, type, params)
        end
      end
    end

    def remove_vindex(table_name, vindex_name, column_name)
      return unless vitess_enabled?

      reversible do |dir|
        dir.up do
          execute <<~SQL
            ALTER VSCHEMA ON #{quote_table_name(table_name)} DROP VINDEX #{quote_table_name(vindex_name)}
          SQL
        end

        dir.down do
          add_vindex(table_name, vindex_name, column_name)
        end
      end
    end

    def drop_vindex(vindex_name, type, params)
      return unless vitess_enabled?

      reversible do |dir|
        dir.up do
          execute <<~SQL
            ALTER VSCHEMA DROP VINDEX #{quote_table_name(vindex_name)}
          SQL
        end

        dir.down do
          create_vindex(vindex_name, type, params)
        end
      end
    end

    def create_sequence(sequence_name)
      return unless vitess_enabled?

      reversible do |dir|
        dir.up do
          execute <<~SQL
            ALTER VSCHEMA ADD SEQUENCE #{quote_table_name(sequence_name)};
          SQL
        end

        dir.down do
          drop_sequence(sequence_name)
        end
      end
    end

    def drop_sequence(sequence_name)
      return unless vitess_enabled?

      reversible do |dir|
        dir.up do
          db_config = ActiveRecord::Base.configurations.configs_for(env_name: Rails.env, name: "vt_primary")
          vschema_path = Rails.root.join(db_config.configuration_hash[:vschema_path])

          VTCombo.drop_sequence(sequence_name)
        end

        dir.down do
          create_sequence(sequence_name)
        end
      end
    end

    def add_auto_increment(table_name, column_name, sequence_name)
      return unless vitess_enabled?

      reversible do |dir|
        dir.up do
          keyspace_name = quote_table_name(ApplicationRecord::VT.connection_db_config.database)

          execute <<~SQL
            ALTER VSCHEMA ON #{quote_table_name(table_name)} ADD AUTO_INCREMENT #{quote_table_name(column_name)} USING #{keyspace_name}.#{quote_table_name(sequence_name)};
          SQL
        end

        dir.down do
          remove_auto_increment(table_name, column_name, sequence_name)
        end
      end
    end

    def remove_auto_increment(table_name, column_name, sequence_name)
      return unless vitess_enabled?

      reversible do |dir|
        dir.up do
          db_config = self.class.connection_specification_name.connection_db_config
          vschema_path = Rails.root.join(db_config.configuration_hash[:vschema_path])

          table_name = quote_table_name(table_name)
          column_name = quote_table_name(column_name)
          sequence_name = quote_table_name(sequence_name)

          VTCombo.drop_auto_increment(db_config, table_name, column_name, sequence_name)
        end

        dir.down do
          add_auto_increment(table_name, column_name, sequence_name)
        end
      end
    end

    def vitess_enabled?
      return false if GitHub.enterprise?

      connection = self.class.connection_specification_name
      connection && connection.connection_db_config.configuration_hash[:vitess]
    end
  end
end
