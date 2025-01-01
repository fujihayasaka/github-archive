# typed: true
# frozen_string_literal: true

require "test_helper"

class SecurityProduct::ActionsChecksTest < GitHub::TestCase
  class TestService < SecurityProduct::Service
    include SecurityProduct::Service::ActionsChecks

    def on_enable(actor:, options:)
      SecurityProduct::Result.new(false, "test service cannot be enabled.")
    end

    def on_disable(actor:, options:)
      SecurityProduct::Result.new(true)
    end

    def enabled?
      false
    end

    def to_sym
      :test_service
    end

    def self.name
      "Test Service"
    end
  end

  setup do
    @repo = create(:repository)
  end

  context "actions_runner_checker" do
    test "it instantiates and caches an actions runner checker on first call" do
      service = TestService.new(@repo)

      checker = service.actions_runner_checker
      assert_kind_of SecurityProductsEnablement::Actions::RunnerChecker, checker
      assert_equal checker.object_id, service.actions_runner_checker.object_id
    end

    test "it accepts an existing runner checker for the same repository" do
      service = TestService.new(@repo)
      checker = SecurityProductsEnablement::Actions::RunnerChecker.new(@repo)

      refute_error_reported do
        service.actions_runner_checker = checker
      end

      assert_equal checker.object_id, service.actions_runner_checker.object_id
    end

    test "it raises an argument error if a caller attempts to replace an existing checker" do
      service = TestService.new(@repo)
      checker = SecurityProductsEnablement::Actions::RunnerChecker.new(@repo)

      refute_error_reported do
        service.actions_runner_checker = checker
      end

      assert_raises(ArgumentError, "SecurityProductsEnablement::Actions::RunnerChecker already assigned") do
        service.actions_runner_checker = checker
      end
    end

    test "it raises an argument error if a caller attempts to assign a checker for a different repository" do
      service = TestService.new(@repo)
      other_repo = create(:repository)
      checker = SecurityProductsEnablement::Actions::RunnerChecker.new(other_repo)

      assert_raises(ArgumentError, "SecurityProductsEnablement::Actions::RunnerChecker already assigned") do
        service.actions_runner_checker = checker
      end
    end
  end
end
