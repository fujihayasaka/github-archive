# typed: strict
# frozen_string_literal: true

# Represents when a user exits the Copilot trial, regardless of the reason.
module LeadSignal
  class Subscriber
    sig { params(copilot_user: Copilot::User, _args: T.untyped).void }
    def copilot_trial_conversion(copilot_user:, **_args)
      user = copilot_user.user_object
      signal_payload = { email: user.email }

      converstion_lead = CopilotTrialConversion.create!(signal_payload)
      exit_lead = CopilotTrialExit.create!(signal_payload)

      log_signal_created(__method__, user.id, [converstion_lead.id, exit_lead.id])
      exit_stats("lead_ingestion.copilot_for_individuals.trial_conversion")
    end

    sig { params(copilot_user: Copilot::User, _args: T.untyped).void }
    def copilot_trial_exit(copilot_user:, **_args)
      user = copilot_user.user_object
      signal_payload = { email: user.email }

      exit_lead = CopilotTrialExit.create!(signal_payload)

      log_signal_created(__method__, user.id, [exit_lead.id])
      exit_stats("lead_ingestion.copilot_for_individuals.trial_exit", reason: "subscription_cancellation")
    end

    sig { params(user: User, _args: T.untyped).void }
    def copilot_cfb_individual_seat_conversion(user:, **_args)
      signal_payload = { email: user.email }

      exit_lead = CopilotTrialExit.create!(signal_payload)

      log_signal_created(__method__, user.id, [exit_lead.id])
      exit_stats("lead_ingestion.copilot_for_individuals.trial_exit", reason: "seat_conversion")
    end

    private

    sig { params(method: T.nilable(Symbol), user_id: T.nilable(Integer), lead_ids: T.nilable(T::Array[String])).void }
    def log_signal_created(method, user_id, lead_ids = [])
      GitHub.logger.info("Lead Signals created", {
        "code.namespace" => "LeadSignal::Subscriber",
        "code.function" => method,
        "gh.user.id" => user_id,
        "gh.lead_ingestion.lead_ids" => lead_ids,
      })
    end

    sig { params(name: String, reason: T.nilable(String)).void }
    def exit_stats(name, reason: nil)
      tags = ["reason:#{reason}"] if reason
      GitHub.dogstats.increment(name, tags: tags)
    end
  end
end
