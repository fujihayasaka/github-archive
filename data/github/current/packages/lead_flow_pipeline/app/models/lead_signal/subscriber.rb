# typed: strict
# frozen_string_literal: true

# Represents when a user exits the Copilot trial, regardless of the reason.
module LeadSignal
  class Subscriber
    extend T::Sig

    sig { params(copilot_user: Copilot::User, _args: T.untyped).void }
    def copilot_trial_conversion(copilot_user:, **_args)
      user = copilot_user.user_object
      signal_payload = { email: user.email }

      CopilotTrialConversion.create!(signal_payload)
      CopilotTrialExit.create!(signal_payload)

      log("Lead Flow Pipeline copilot trial conversion signals enqueued", __method__, user.id)
      exit_stats("lead_ingestion.copilot_for_individuals.trial_conversion")
    end

    sig { params(copilot_user: Copilot::User, _args: T.untyped).void }
    def copilot_trial_exit(copilot_user:, **_args)
      user = copilot_user.user_object
      signal_payload = { email: user.email }

      CopilotTrialExit.create!(signal_payload)

      log("Lead ingestion copilot subscription cancellation signal enqueued", __method__, user.id)
      exit_stats("lead_ingestion.copilot_for_individuals.trial_exit", reason: "subscription_cancellation")
    end

    sig { params(user: User, _args: T.untyped).void }
    def copilot_cfb_individual_seat_conversion(user:, **_args)
      signal_payload = { email: user.email }

      CopilotTrialExit.create!(signal_payload)

      log("Lead ingestion copilot cfb individual seat conversion signal enqueued", __method__, user.id)
      exit_stats("lead_ingestion.copilot_for_individuals.trial_exit", reason: "seat_conversion")
    end

    private

    sig { params(message: String, method: T.nilable(Symbol), user_id: T.nilable(Integer)).void }
    def log(message, method, user_id)
      GitHub.logger.info(message, {
        "code.namespace" => "LeadSignal::Subscriber",
        "code.function" => method,
        "gh.user.id" => user_id,
      })
    end

    sig { params(name: String, reason: T.nilable(String)).void }
    def exit_stats(name, reason: nil)
      tags = ["reason:#{reason}"] if reason
      GitHub.dogstats.increment(name, tags: tags)
    end
  end
end
