# typed: true
# frozen_string_literal: true
class CopilotBaseMailer < ApplicationMailer
  layout "layouts/copilot"

  after_deliver :log_delivery

  around_deliver do |_mailer, block|
    T.bind(self, CopilotBaseMailer)
    unless skip_email?
      if GitHub.flipper[:copilot_mail_logger].enabled?
        set_message_id
        GitHub.logger.with_named_tags(
          "code.function" => @_action_name.to_s,
          "code.namespace" => self.class.name,
          "gh.copilot.message_id" => mail.message_id || "unknown",
          "gh.copilot.mailable.id" => mailable&.id.to_s,
          "gh.copilot.mailable.class" => mailable&.class&.name || "unknown",
        ) do
          GitHub.logger.info "Delivering Copilot message"
          block.call
        end
      else
        block.call
      end
    end
  end

  def log_delivery
    return if skip_email?
    return unless GitHub.flipper[:copilot_mail_logger].enabled?
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
    Copilot.copilot_communication_opt_out?(mailable)
  end
end
