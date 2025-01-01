# typed: true
# frozen_string_literal: true

require "rails/generators"
require "rails/generators/migration"
require "rails/generators/active_record"

class ArchivalModelGenerator < Rails::Generators::NamedBase
  include Rails::Generators::Migration

  source_root File.expand_path("../templates", __FILE__)

  def check_model
    return if self.behavior == :revoke

    unless known_model?
      puts "#{class_name} is not a known ActiveRecord model. Try again?"
      exit
    end
  end

  def generate_migration
    if !archival_model_exists? || self.behavior == :revoke
      migration_template "migration.rb.erb", "db/migrate/create_archived_#{plural_file_name}.rb"
    end
  end

  def generate_archived_model
    if !archival_model_exists? || self.behavior == :revoke
      template "archived_model.rb.erb", "app/models/archived/#{file_name}.rb"
    end
  end

  def generate_archived_model_test
    template "archived_model_test.rb.erb", "test/models/archived/#{file_name}_test.rb"
  end

  def configure_associations
    return if self.behavior == :revoke

    ar_model.reflections.each_value do |reflection|
      next if reflection.options[:polymorphic]
      next if reflection.class_name == class_name
      next unless archival_model_exists?(reflection.class_name || reflection.klass.name)
      inject_into_file "app/models/archived/#{file_name}.rb", after: "Archived::Base\n" do
        indent %Q[#{reflection.macro} :#{reflection.name}, :class_name => "Archived::#{reflection.class_name}"#{", :dependent => :delete_all" if reflection.macro == :has_many}\n]
      end
    end
  end

  def self.next_migration_number(dir)
    Time.now.utc.strftime("%Y%m%d%H%M%S")
  end

  private

  def ar_model
    Module.const_get(class_name)
  end

  def known_model?
    ar_model.new.is_a?(ActiveRecord::Base)
  rescue NameError
    false
  end

  def archival_model_exists?(klass = class_name)
    "Archived::#{klass}".constantize <= Archived::Base
  rescue NameError
    false
  end

  def max_column_name_length
    @max_column_name_length ||=
      ar_model.columns.map(&:name).sort_by(&:length).last.length
  end

  def max_column_type_length
    @max_column_type_length ||=
      ar_model.columns.map(&:sql_type).sort_by(&:length).last.length
  end
end
