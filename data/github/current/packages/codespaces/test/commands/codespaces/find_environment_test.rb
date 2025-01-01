# typed: true
# frozen_string_literal: true

require "test_helper"

module Codespaces
  class FindEnvironmentTest < GitHub::TestCase
    self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
    fixtures do
      @monalisa = create(:paid_user, name: "monalisa")
      @plan = create(:codespace_plan)
      @codespace = create(:codespace, :unprovisioned, owner: @monalisa, plan: @plan)
      @other_codespace = create(:codespace, :unprovisioned, owner: @monalisa, plan: @plan)
      @guid = SecureRandom.uuid
      @environment = {
        "id" => @guid,
        "friendlyName" => @codespace.name,
        "updated" => Time.current
      }
      FakeVSOServer.environments = [@environment]
    end

    context "call" do
      test "returns the environment when it exists" do
        env = Codespaces::FindEnvironment.call(@codespace)
        assert_equal @codespace.name, env.name
        assert_equal @guid, env.id
      end

      test "returns an environment when there are duplicates" do
        # Add the same environment twice to mimic duplicates in VSCS
        FakeVSOServer.environments << {
          "id" => SecureRandom.uuid,
          "friendlyName" => @codespace.name,
          "updated" => Time.current
        }

        env = Codespaces::FindEnvironment.call(@codespace)
        assert_equal @codespace.name, env.name
        assert_equal @guid, env.id
      end

      test "returns nil when the environment cannot be found" do
        env = Codespaces::FindEnvironment.call(@other_codespace)
        assert_nil env
      end
    end

    context "call!" do
      test "raises NotFound when an environment cannot be found" do
        assert_raises Codespaces::FindEnvironment::NotFoundError do
          Codespaces::FindEnvironment.call!(@other_codespace)
        end
      end

      test "masks timeout errors as NotFound errors" do
        Codespaces::VscsClient.any_instance.stubs(:list_environments).raises(Codespaces::Client::TimeoutError.new("BOOM!"))
        assert_raises Codespaces::FindEnvironment::NotFoundError do
          Codespaces::FindEnvironment.call!(@codespace)
        end
      end
    end
  end
end
