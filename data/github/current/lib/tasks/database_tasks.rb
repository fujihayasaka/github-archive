# typed: true
# frozen_string_literal: true

require "progeny"

module ActiveRecord
  module Tasks
    class MySQLDatabaseTasks
      def structure_load_spawn(filename)
        args = prepare_command_options
        args.concat(["--execute", %{SET FOREIGN_KEY_CHECKS = 0; SOURCE #{filename}; SET FOREIGN_KEY_CHECKS = 1}])
        database_name = "#{configuration_hash[:database]}"
        args.concat(["--database", database_name])
        # Using T.unsafe to support the Splat operator https://sorbet.org/docs/error-reference#7019
        process = T.unsafe(Progeny::Command).new("mysql", *args)
        unless process.status.success?
          raise "Importing MySQL structure #{filename} failed: #{process.err}"
        end
      end
    end
  end
end
