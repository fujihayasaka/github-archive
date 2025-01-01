# frozen_string_literal: true

namespace :db do
  namespace :schema do
    desc "Remove all AUTO_INCREMENT values from the schema"
    task remove_auto_increments: :environment do
      # prior to our rails 7.1.2 upgrade, this was
      # path = File.join(ActiveRecord::Tasks::DatabaseTasks.db_dir,
      #   ActiveRecord::Tasks::DatabaseTasks.schema_file_type(
      #     ActiveRecord.schema_format,
      #   ))
      # But Rails removed ActiveRecord::Tasks::DatabaseTasks.schema_file_type.
      # Manually maintaining this name seems fine

      path = File.join(ActiveRecord::Tasks::DatabaseTasks.db_dir, "structure.sql")

      File.atomic_write(path) do |write_file|
        File.open(path) do |read_file|
          read_file.each_line do |line|
            line.gsub!(/ AUTO_INCREMENT=\d+/, "")
            write_file.write(line)
          end
        end
      end
    end
  end
end

Rake::Task["db:schema:dump"].enhance do
  Rake::Task["db:schema:remove_auto_increments"].execute
end
