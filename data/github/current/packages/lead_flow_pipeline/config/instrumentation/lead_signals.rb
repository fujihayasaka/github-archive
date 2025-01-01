# typed: true
# frozen_string_literal: true

# Subscribe to Copilot trial conversion events
GlobalInstrumenter.subscribe("copilot.trial_subscription_converts") do |_, _, _, _, payload|
  subscriber = LeadSignal::Subscriber.new
  subscriber.copilot_trial_conversion(**payload)
end

GlobalInstrumenter.subscribe("copilot.subscription_cancelled") do |_, _, _, _, payload|
  subscriber = LeadSignal::Subscriber.new
  subscriber.copilot_trial_exit(**payload)
end

GlobalInstrumenter.subscribe("copilot.cfb_individual_seat_converted") do |_, _, _, _, payload|
  subscriber = LeadSignal::Subscriber.new
  subscriber.copilot_cfb_individual_seat_conversion(**payload)
end
