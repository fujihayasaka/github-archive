# typed: true
# frozen_string_literal: true

RAILS_PATH = Pathname.new(File.expand_path("../../../../", __FILE__))
LOCALIZATION_PACKAGE_PATH = RAILS_PATH.join("packages/localization")

class LocalizationTestSupport
  def self.require_rails_file(file)
    require "#{RAILS_PATH}/#{file}"
  end

  def self.require_support(file)
    require "#{LOCALIZATION_PACKAGE_PATH}/test/support/#{file}"
  end
end

if ENV["LOCALIZATION_FAST_TESTS"].to_i.positive?
  if ENV["CI"]
    raise "Fast helper should not have been included"
  end
  LocalizationTestSupport.require_support("setup_fast_tests.rb")
else
  require "test_helper"
end
