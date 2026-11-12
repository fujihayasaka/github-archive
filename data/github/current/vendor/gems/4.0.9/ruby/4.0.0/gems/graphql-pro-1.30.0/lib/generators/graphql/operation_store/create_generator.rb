# frozen_string_literal: true
module Graphql
  module Generators
    module OperationStore
      class CreateGenerator < Rails::Generators::Base
        include Rails::Generators::Migration

        desc "Create the migration file for GraphQL::Pro::OperationStore"
        source_root File.expand_path('../templates', __FILE__)

        class << self
          # Implement the required interface for Rails::Generators::Migration.
          def next_migration_number(dirname)
            next_migration_number = current_migration_number(dirname) + 1
            ActiveRecord::Migration.next_migration_number(next_migration_number)
          end
        end

        def add_migration
          puts "ADding migration"
          migration_template "migration.erb", "db/migrate/setup_operation_store.rb"
        end
      end
    end
  end
end
