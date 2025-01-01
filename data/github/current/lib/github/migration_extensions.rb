# typed: true
# frozen_string_literal: true
# rubocop:disable GitHub/DoNotCallMethodsOnActiveRecordBase

if GitHub.enterprise?
  # ensure all the transitions are loaded
  require "github/legacy_transition"
  require "github/transition"

  transitions_dir = File.join(__FILE__, "..", "transitions")
  Dir["#{transitions_dir}/*.rb"].each do |transition|
    require "github/transitions/#{File.basename(transition, '.rb')}"
  end
end

require "github/vitess_migration_extensions"

module GitHub::MigrationExtensions
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { ActiveRecord::Migration }
  include Kernel

  include GitHub::VitessMigrationExtensions

  included do
    prepend GitHub::MigrationExtensions::PrependMethods
  end

  class_methods do
    def multi_db_enabled?
      !GitHub.enterprise?
    end

    def connection_specification_name=(name)
      return unless multi_db_enabled?
      @spec_name = name
    end

    def connection_specification_name
      @spec_name
    end

    def use_connection_class(klass)
      self.connection_specification_name = klass
    end
  end

  module PrependMethods
    include Kernel

    def exec_migration(conn, direction)
      return super unless self.class.connection_specification_name

      self.class.connection_specification_name.with_connection do |class_conn|
        super(class_conn, direction)
      end
    end
  end
end
