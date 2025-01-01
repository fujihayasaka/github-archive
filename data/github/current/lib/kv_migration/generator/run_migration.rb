# typed: true
# frozen_string_literal: true

require "kv_migration/generator/utils"

module KvMigration
  module Generator
    class RunMigration
      def self.call
        puts "Running bin/rake db:migrate db:test:prepare"
        Kernel.exec("bin/rake", "db:migrate", "db:test:prepare")
      end
    end
  end
end
