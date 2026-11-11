# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "test"
require File.expand_path("../config/environment", __dir__)

# Prevent database truncation if the environment is production
raise "The Rails environment is running in production mode!" if Rails.env.production?

require "spec_helper"
require "rspec/rails"
require "coach/rspec"

Dir[Rails.root.join("spec/support/**/*.rb")].sort.each { |f| require f }

ActiveRecord::Migration.maintain_test_schema!

RSpec.configure do |config|
  config.fixture_paths = [Rails.root.join("spec/fixtures")]
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  config.include ChecksumHelpers
  config.include FixtureHelpers
  config.include HydroTestHelpers
  config.include PaginationTestHelpers
  config.include FactoryBot::Syntax::Methods

  @log_db = false
  @default_logger = nil

  config.before do |example|
    Dependabot.hydro_sink.reset
    @log_db = example.metadata[:log_db]

    if defined?(ActiveRecord::Base) && @log_db
      @default_logger = ActiveRecord::Base.logger
      ActiveRecord::Base.logger = Logger.new($stdout)
    end
  end

  config.after do |_example|
    ActiveRecord::Base.logger = @default_logger if defined?(ActiveRecord::Base) && @log_db
  end
end

require "./lib/dependabot/logger"
Dependabot::Logger.disable
