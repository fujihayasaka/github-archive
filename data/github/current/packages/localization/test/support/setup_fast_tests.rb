# typed: ignore
# frozen_string_literal: true

if defined?(Bundler) || ENV["CI"]
  return
end

require "zeitwerk"
require "mocha/minitest"
require "webmock"
require "action_view/helpers/number_helper"
require "money/bank/open_exchange_rates_bank"
require "gettext_i18n_rails"
require "html/pipeline"

loader = Zeitwerk::Loader.for_gem
loader.push_dir(LOCALIZATION_PACKAGE_PATH.join("app/models"))
loader.push_dir(LOCALIZATION_PACKAGE_PATH.join("app"))
loader.push_dir(LOCALIZATION_PACKAGE_PATH.join("app/public"))
loader.push_dir(RAILS_PATH.join("app/models"))
loader.push_dir(LOCALIZATION_PACKAGE_PATH.join("test/support/lib"))

loader.inflector.inflect(
  "github" => "GitHub",
)

loader.setup

LocalizationTestSupport.require_support("rails")
LocalizationTestSupport.require_support("github/test_case")
LocalizationTestSupport.require_rails_file("config/initializers/i18n.rb")

GitHub.extend(Mocks::GitHub)
User = Class.new(Mocks::User)
