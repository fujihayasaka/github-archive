# typed: true
# frozen_string_literal: true

require "rails/generators"

class FeatureGenerator < Rails::Generators::NamedBase
  include Rails::Generators::Migration

  source_root File.expand_path("../templates", __FILE__)
  class_option :description, type: :string
  class_option :flipper_feature_name, type: :string
  class_option :enterprise, type: :boolean, default: false
  class_option :feedback_link, type: :string
  class_option :enrolled_by_default, type: :boolean, default: false

  def self.next_migration_number(dir)
    Time.now.utc.strftime("%Y%m%d%H%M%S")
  end

  def generate_transition_file
    template "feature_transition.rb.erb", "lib/github/transitions/create_#{file_name}_feature.rb"
  end

  def generate_transition_test_file
    template "feature_transition_test.rb.erb", "test/lib/github/transitions/create_#{file_name}_feature_test.rb"
  end

  def generate_migration_file
    if options["enterprise"] == true
      migration_template "feature_migration.rb.erb", "db/migrate/create_#{file_name}_feature.rb"
    end
  end
end
