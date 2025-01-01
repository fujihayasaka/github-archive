# typed: true
# frozen_string_literal: true

ActiveRecord::Tasks::DatabaseTasks.register_task("trilogy", "ActiveRecord::Tasks::MySQLDatabaseTasks")

# Use these GitHub specific flags when dumping the database structure.
# The following flags will be appended to Rails default flags.
ActiveRecord::Tasks::DatabaseTasks.structure_dump_flags = [
  "--set-gtid-purged=OFF"
]
