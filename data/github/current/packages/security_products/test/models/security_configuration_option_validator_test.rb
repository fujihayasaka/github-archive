# typed: true
# frozen_string_literal: true

require "test_helper"

class SecurityConfigurationOptionValidatorTest < ActiveSupport::TestCase
  extend T::Helpers

  class MockOptions < SecurityProduct::Service::Options
    option :runner_type, default: "mid"
    validates :runner_type, inclusion: { in: %w[smol mid extra], message: "must be one smol, mid or extra" }

    option :runner_label, default: "mock"
    validates :runner_label, presence: true, length: { minimum: 4 }
  end

  def create_config(opts_hash, feature_state: "enabled")
    SecurityConfiguration.new(
      dependency_graph_autosubmit_action: feature_state,
      dependency_graph_autosubmit_action_options: opts_hash
    )
  end

  def setup
    @validator = SecurityConfigurationOptionValidator.new(columns: {
      dependency_graph_autosubmit_action_options: MockOptions,
    })
  end

  test "is valid when defaults are used" do
    config = create_config({})
    @validator.validate(config)
    assert_empty config.errors
  end

  test "is valid when the defaults are used and the feature is disabled" do
    config = create_config({}, feature_state: "disabled")
    @validator.validate(config)
    assert_empty config.errors
  end

  test "is valid when the defaults are used and the feature is not_set" do
    config = create_config({}, feature_state: "not_set")
    @validator.validate(config)
    assert_empty config.errors
  end

  test "attaches an error if non-default options are passed and the feature is disabled" do
    config = create_config({ runner_label: "foobar" }, feature_state: "disabled")
    @validator.validate(config)
    refute_empty config.errors

    assert_equal "Dependency graph autosubmit action options cannot be set when the feature is disabled",
                 config.errors[:dependency_graph_autosubmit_action_options].first
  end

  test "attaches an error if non-default options are passed and the feature is not_set" do
    config = create_config({ runner_label: "foobar" }, feature_state: "not_set")
    @validator.validate(config)
    refute_empty config.errors

    assert_equal "Dependency graph autosubmit action options cannot be set when the feature is not set",
                 config.errors[:dependency_graph_autosubmit_action_options].first
  end

  test "attaches errors for invalid options" do
    config = create_config({ runner_label: "foo" })
    @validator.validate(config)
    refute_empty config.errors

    assert_equal "Runner label is too short (minimum is 4 characters)",
                 config.errors[:dependency_graph_autosubmit_action_options].first.full_message
  end

  test "attaches multiple errors for invalid options" do
    config = create_config({ runner_type: "extra-extra", runner_label: nil })
    @validator.validate(config)
    refute_empty config.errors

    opts_errors = config.errors[:dependency_graph_autosubmit_action_options].map(&:full_message)

    assert_includes opts_errors, "Runner type must be one smol, mid or extra"
    assert_includes opts_errors, "Runner label can't be blank"
    assert_includes opts_errors, "Runner label is too short (minimum is 4 characters)"
  end
end
