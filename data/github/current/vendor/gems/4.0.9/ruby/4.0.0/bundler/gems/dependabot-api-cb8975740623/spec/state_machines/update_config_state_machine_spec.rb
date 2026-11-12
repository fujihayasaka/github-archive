# frozen_string_literal: true

require "rails_helper"

RSpec.describe UpdateConfigStateMachine do
  describe "after_transition to :deleted" do
    let(:update_config) { create(:update_config, :active, next_enqueue_at: 1.day.from_now) }

    it "sets next_enqueue_at to nil" do
      update_config.transition_to!(:deleted)

      expect(update_config.reload.next_enqueue_at).to be_nil
    end
  end

  describe "after_transition to :active" do
    let(:update_config) do
      create(:update_config, :rate_limited,
             update_schedule_cron_expression: "0 9 * * 1-5 UTC",
             next_enqueue_at: nil)
    end

    it "sets next_enqueue_at from cron expression" do
      update_config.transition_to!(:active)

      expect(update_config.reload.next_enqueue_at).to be_a(Time)
    end

    it "respects the timezone in the cron expression" do
      update_config.update_column(:update_schedule_cron_expression, "0 9 * * 1-5 America/New_York")
      update_config.transition_to!(:active)

      expect(update_config.reload.next_enqueue_at.hour).not_to eq(9)
    end
  end

  describe "after_transition to :rate_limited" do
    let(:update_config) do
      create(:update_config, :pending, update_schedule_cron_expression: "0 9 * * 1-5 UTC")
    end

    it "sets next_enqueue_at from cron expression" do
      expect { update_config.transition_to!(:rate_limited) }.
        to change { update_config.reload.next_enqueue_at }.from(nil)
    end
  end

  describe "denormalizing current state" do
    let(:update_config) { create(:update_config, :pending) }

    it "sets the current_state column on transition" do
      expect(update_config.current_state).to eq("pending")

      update_config.transition_to!(:rate_limited)
      update_config.reload
      expect(update_config.attributes["current_state"]).to eq("rate_limited")

      update_config.transition_to!(:active)
      update_config.reload
      expect(update_config.attributes["current_state"]).to eq("active")
    end

    it "resetting the state machine reloads the denormalized column" do
      update_config.current_state = "rate_limited"
      update_config.state_machine.reset
      expect(update_config.current_state).to eq("pending")
    end
  end
end
