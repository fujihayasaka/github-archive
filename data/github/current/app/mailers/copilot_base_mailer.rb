# typed: true
# frozen_string_literal: true

class CopilotBaseMailer < ApplicationMailer
  layout "layouts/copilot"

  ALWAYS_SEND_EMAIL_ACTIONS = T.let(%w[
    premium_usage_report
    premium_usage_report_no_data
    activity_report
    activity_report_no_data
    activity_report_download
  ].freeze, T::Array[String])

  after_deliver :log_delivery

  around_deliver do |_mailer, block|
    T.bind(self, CopilotBaseMailer)
    unless skip_email?
      set_message_id
      GitHub.logger.with_named_tags(
        "code.function" => @_action_name.to_s,
        "code.namespace" => self.class.name,
        "gh.copilot.message_id" => mail.message_id || "unknown",
        "gh.copilot.mailable.id" => mailable&.id.to_s,
        "gh.copilot.mailable.class" => mailable&.class&.name || "unknown",
      ) do
        GitHub.logger.info "Delivering Copilot message"

        result = block.call

        GitHub.logger.info("Copilot mailer action returned",
          "gh.copilot.mailer.action_return_class" => result.class.name,
          "gh.copilot.mailer.has_errors" => result.errors&.present?
        )

        result
      end
    end
  end

  def log_delivery
    return if skip_email?

    GitHub.logger.with_named_tags(
      "code.function" => @_action_name.to_s,
      "code.namespace" => self.class.name,
      "gh.copilot.message_id" => mail.message_id || "unknown",
      "gh.copilot.mailer_action" => @_action_name.to_s,
      "gh.copilot.mailable.id" => mailable&.id.to_s,
      "gh.copilot.mailable.class" => mailable&.class&.name || "unknown",
    ) do
      GitHub.logger.info "Delivered Copilot message"
    end
  end

  # these shut up sorbet
  def self.mail; end

  # We don't always have a User (some of the emails go to groups)
  # so we identify a "mailable" object that we can use to identify
  # the recipient(s) of the email.
  sig { returns(T.nilable(T.any(::User, ::Organization, ::Business))) }
  def mailable
    raise NotImplementedError, "Must implement #mailable for logging."
  end

  def set_message_id
    name = @_action_name || "copilot"
    mailable_id = mailable&.id || "unknown"
    mailable_class = mailable&.class&.name || "unknown"
    message_id = "#{name}/#{mailable_id}_#{SecureRandom.hex}".downcase
    mail.message_id = "<#{message_id}@#{GitHub.urls.host_name}>"
  end

  sig { returns(T::Boolean) }
  def skip_email?
    always_send_email_actions_enabled = FeatureFlag.vexi.enabled?(
      :copilot_always_send_email_actions,
      mailable,
      default: false
    )
    is_always_send_action = ALWAYS_SEND_EMAIL_ACTIONS.include?(action_name.to_s)

    if is_always_send_action && always_send_email_actions_enabled
      GitHub.logger.info("Sending email because #{action_name} is in ALWAYS_SEND_EMAIL_ACTIONS")
    end

    return false if always_send_email_actions_enabled && is_always_send_action

    should_skip = Copilot.copilot_communication_opt_out?(mailable)

    if should_skip
      GitHub.logger.info("Skipping Copilot email due to user opt-out")
    end

    should_skip
  end
end
