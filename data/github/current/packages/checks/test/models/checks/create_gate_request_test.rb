# typed: true
# frozen_string_literal: true

require "test_helper"

class Checks::CreateGateRequestTest < GitHub::TestCase
  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    make_trusted_oauth_apps_owner

    @expires_at = Time.now

    @owner = create(:user)
    @repo = create(:repository, owner: @owner)
    @check_suite = create(:check_suite_for_actions_app, repository: @repo)
    @check_run = create(:check_run_for_actions_app, check_suite: @check_suite)

    environment = create(:environment, repository: @repo)
    @gate = create(:gate, environment: environment)
  end

  test "it creates a new closed gate request" do
    update_properties = {
      token: "token",
      gate_state: "closed",
      concluded: false,
      gate_id: @gate.id,
      check_run_id: @check_run.id,
      expires_at: @expires_at,
    }

    subject = Checks::CreateGateRequest.new(check_run: @check_run, update_properties: update_properties)

    assert_difference -> { GateRequest.count }, 1 do
      subject.call
    end

    gate_request = GateRequest.last

    assert(T.must(gate_request).attributes >= {
      "token" => "token",
      "state" => "closed",
      "gate_id" => @gate.id,
      "check_run_id" => @check_run.id,
    })
  end

  test "it creates a new open gate request" do
    update_properties = {
      token: "token",
      gate_state: "open",
      concluded: false,
      gate_id: @gate.id,
      check_run_id: @check_run.id,
      expires_at: @expires_at,
    }

    subject = Checks::CreateGateRequest.new(check_run: @check_run, update_properties: update_properties)

    assert_difference -> { GateRequest.count }, 1 do
      subject.call
    end

    gate_request = GateRequest.last

    assert(T.must(gate_request).attributes >= {
      "token" => "token",
      "state" => "open",
      "gate_id" => @gate.id,
      "check_run_id" => @check_run.id,
    })
  end

  test "it creates a new rejected gate request" do
    update_properties = {
      token: "token",
      gate_state: "rejected",
      concluded: true,
      gate_id: @gate.id,
      check_run_id: @check_run.id,
      expires_at: @expires_at,
    }

    subject = Checks::CreateGateRequest.new(check_run: @check_run, update_properties: update_properties)

    assert_difference -> { GateRequest.count }, 1 do
      subject.call
    end

    gate_request = GateRequest.last

    assert(T.must(gate_request).attributes >= {
      "token" => "token",
      "state" => "rejected",
      "gate_id" => @gate.id,
      "check_run_id" => @check_run.id,
    })
  end

  test "it creates a new concluded closed gate request" do
    update_properties = {
      token: "token",
      gate_state: "closed",
      concluded: true,
      gate_id: @gate.id,
      check_run_id: @check_run.id,
      expires_at: @expires_at,
    }

    subject = Checks::CreateGateRequest.new(check_run: @check_run, update_properties: update_properties)

    assert_difference -> { GateRequest.count }, 1 do
      subject.call
    end

    gate_request = GateRequest.last

    assert(T.must(gate_request).attributes >= {
      "token" => "token",
      "state" => "rejected",
      "gate_id" => @gate.id,
      "check_run_id" => @check_run.id,
    })
  end
end
