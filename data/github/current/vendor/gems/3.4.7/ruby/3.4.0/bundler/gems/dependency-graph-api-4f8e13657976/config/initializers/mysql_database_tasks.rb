ActiveRecord::Tasks::DatabaseTasks.register_task("trilogy", "ActiveRecord::Tasks::MySQLDatabaseTasks")

ActiveRecord::Tasks::DatabaseTasks.structure_dump_flags = [
  "--set-gtid-purged=OFF"
]
