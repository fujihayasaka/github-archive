# frozen_string_literal: true

require "faker"
require "formatter_overrides"
require "rspec/github"
require "vcr"
require "webmock/rspec"

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
    expectations.on_potential_false_positives = :raise
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.before do
    %i(timing time increment count gauge distribution histogram distribution_time).each do |method|
      allow(MetricsClient).to receive(method).and_call_original
    end
  end

  config.around(:each, enterprise: true) do |example|
    if Dependabot.enterprise?
      example.run
    else
      example.skip
    end
  end

  config.around(:each, proxima: true) do |example|
    if Dependabot.proxima?
      example.run
    else
      example.skip
    end
  end

  config.around(:each, proxima: false) do |example|
    if Dependabot.proxima?
      example.skip
    else
      example.run
    end
  end

  config.around(:each, cloud: true) do |example|
    if Dependabot.enterprise? || Dependabot.proxima?
      example.skip
    else
      example.run
    end
  end

  config.after do
    WebMock.reset!
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = "spec/examples.txt"
  config.disable_monkey_patching!
  config.default_formatter = "doc" if config.files_to_run.one?
  config.profile_examples = 10
  config.order = :random

  Kernel.srand config.seed
end

RSpec::Matchers.define_negated_matcher :not_change, :change

RSpec::Github::Formatter.prepend FormatterOverrides

VCR.configure do |config|
  config.cassette_library_dir = "spec/fixtures/vcr_cassettes"
  config.hook_into :webmock
  config.configure_rspec_metadata!
  config.allow_http_connections_when_no_cassette = false

  config.filter_sensitive_data("<AWS_ACCESS_KEY_ID>") do
    ENV["AWS_ACCESS_KEY_ID"]
  end

  config.filter_sensitive_data("<AWS_SECRET_ACCESS_KEY>") do
    ENV["AWS_SECRET_ACCESS_KEY"]
  end

  config.filter_sensitive_data("<AUTHORIZATION>") do |interaction|
    interaction.request.headers["Authorization"]&.first
  end

  config.filter_sensitive_data("<AZURE_STORAGE_ACCESS_KEY>") do
    ENV["AZURE_STORAGE_ACCESS_KEY"]
  end

  # Prevent access tokens being written to VCR cassettes
  unless ENV["DEPENDABOT_TEST_ACCESS_TOKEN"].nil?
    config.filter_sensitive_data("<TOKEN>") do
      ENV["DEPENDABOT_TEST_ACCESS_TOKEN"]
    end
  end

  # Let's you set default VCR mode with VCR=all for re-recording
  # episodes. :once is VCR default
  record_mode = ENV["VCR"] ? ENV["VCR"].to_sym : :once
  config.default_cassette_options = { record: record_mode }
end

RSpec.shared_context "chatops controller" do
  before(:all) do
    ENV["CHATOPS_SERVICE"] = "true"
    Rails.application.reload_routes!
  end

  before do
    chatops_prefix "dependabot"
    chatops_auth!
  end

  after(:all) do
    ENV.delete("CHATOPS_SERVICE")
    Rails.application.reload_routes!
  end
end

RSpec.shared_context "internal twirp api" do
  before(:all) do
    ENV["INTERNAL_DEPLOYMENT"] = "true"
    Rails.application.reload_routes!
  end

  after(:all) do
    ENV.delete("INTERNAL_DEPLOYMENT")
    Rails.application.reload_routes!
  end
end
