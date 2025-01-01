# typed: true
# frozen_string_literal: true

module CustomMessagesHelper
  include GitHub::Memoizer

  # EXAMPLE USAGE
  # <%= customized(:suspended_message) %>
  def customized(type)
    return "" unless GitHub.enterprise?
    return "" unless [:sign_in_message, :sign_out_message, :suspended_message].include?(type)
    ::CustomMessages.instance.public_send(type).to_s
  end

  def default_suspended_message
    if GitHub.enterprise?
      @message = enterprise_suspended_message
    else
      @message = "Access to your account has been suspended due to a violation of our
      [Terms of Service](#{GitHub.help_url}/articles/github-terms-of-service).<br><br>
      Please [contact support](#{GitHub.contact_support_url}/reinstatement) for more information."
    end
  end

  def enterprise_suspended_message
    msg = if GitHub::Enterprise.license.reached_seat_limit? && GitHub.reactivate_suspended_user?
      "There are not enough available licenses to reactivate your suspended user account. Please contact your GitHub Enterprise Server administrator."
    else
      "Sorry. Your account is suspended. Please check with your enterprise account administrator."
    end

    link = " #{GitHub.support_link_text}" if GitHub.support_link_not_enterprise_default?

    "#{msg}#{link}"
  end

  memoize def current_mandatory_message
    MandatoryMessage.value
  end
end
