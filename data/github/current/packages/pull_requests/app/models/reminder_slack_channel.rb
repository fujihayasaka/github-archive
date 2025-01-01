# typed: true
# frozen_string_literal: true

module ReminderSlackChannel
  extend T::Helpers
  extend ActiveSupport::Concern
  requires_ancestor { ActiveRecord::Base }

  # These errors are copied from https://api.slack.com/methods/chat.postMessage#errors
  # Errors that the user _could_ act on have been given messages, others have been assigned to nil
  SLACK_ERRORS = {
    # Value passed for channel was invalid.
    # We expect this one when the channel is invalid
    "channel_not_found" => "The channel (%s) was not found. Check that it exists and that @github has been invited to it",

    # Channel associated with client_msg_id was invalid.
    "duplicate_channel_not_found" => "The channel (%s) was not found. Check that it exists and that @github has been invited to it",

    # No duplicate message exists associated with client_msg_id.
    "duplicate_message_not_found" => nil,

    # Cannot post user messages to a channel they are not in.
    "not_in_channel" => nil,

    # Channel has been archived.
    "is_archived"  => "The channel was archived",

    # Message text is too long
    "msg_too_long" => nil,

    # No message text provided
    "no_text" => nil,

    # A workspace preference prevents the authenticated user from posting.
    "restricted_action" => "Your Slack Workspace settings restricted GitHub from posting",

    # Cannot post any message into a read-only channel.
    "restricted_action_read_only_channel" => "The selected channel was read-only in Slack",

    # Cannot post top-level messages into a thread-only channel.
    "restricted_action_thread_only_channel" => "The selected channel was a thread only channel, which is unsupported",

    # Cannot post thread replies into a non_threadable channel.
    "restricted_action_non_threadable_channel" => nil,

    # Too many attachments were provided with this message. A maximum of 100 attachments are allowed on a message.
    "too_many_attachments" => nil,

    # Application has posted too many messages, read the Rate Limit documentation for more information
    "rate_limited" => "There was an error with Slack, please try again in a few moments",

    # The as_user parameter does not function with workspace apps.
    "as_user_not_supported" => nil,

    # Administrators have suspended the ability to post a message.
    "ekm_access_denied" => "Your Slack Workspace settings have disallowed posting right now",

    # No authentication token provided.
    "not_authed" => nil,

    # Some aspect of authentication cannot be validated. Either the provided token is invalid or the request originates from an IP address disallowed from making the request.
    "invalid_auth" => nil,

    # Authentication token is for a deleted user or workspace.
    "account_inactive" => "We couldn't communicate with Slack, this may be because the user that installed the app was deactivated. Please try installing the GitHub Slack app again",

    # Authentication token is for a deleted user or workspace or the app has been removed.
    "token_revoked" => "We couldn't communicate with Slack, this may be because the user that installed the app was deactivated. Please try installing the GitHub Slack app again",

    # The workspace token used in this request does not have the permissions necessary to complete the request. Make sure your app is a member of the conversation it's attempting to post a message to.
    "no_permission" => "We don't seem to have access to this channel. Can you invite the GitHub bot to this Slack channel and try again?",

    # The workspace is undergoing an enterprise migration and will not be available until migration is complete.
    "org_login_required" => "Your Slack Workspace is undergoing maintenance. Please wait for that maintenance to complete",

    # The token used is not granted the specific scope permissions required to complete this request.
    "missing_scope" => nil,

    # The method was called with invalid arguments.
    "invalid_arguments" => nil,

    # The method was passed an argument whose name falls outside the bounds of accepted or expected values. This includes very long names and names with non-alphanumeric characters other than _. If you get this error, it is typically an indication that you have made a very malformed API call.
    "invalid_arg_name" => nil,

    # The method was called via a POST request, but the charset specified in the Content-Type header was invalid. Valid charset names are: utf-8 iso-8859-1.
    "invalid_charset" => nil,

    # The method was called via a POST request with Content-Type application/x-www-form-urlencoded or multipart/form-data, but the form data was either missing or syntactically invalid.
    "invalid_form_data" => nil,

    # The method was called via a POST request, but the specified Content-Type was invalid. Valid types are: application/json application/x-www-form-urlencoded multipart/form-data text/plain.
    "invalid_post_type" => nil,

    # The method was called via a POST request and included a data payload, but the request did not include a Content-Type header.
    "missing_post_type"  => nil,

    # The workspace associated with your request is currently undergoing migration to an Enterprise Organization. Web API and other platform operations will be intermittently unavailable until the transition is complete.
    "team_added_to_org"  => "Your Slack workspace is undergoing maintenance. Please wait until Slack finishes this migration before trying again",

    # The method was called via a POST request, but the POST data was either missing or truncated.
    "request_timeout" => "Slack timed out while we were communicating with them. Please try again",

    # The server could not complete your operation(s) without encountering a catastrophic error. It's possible some aspect of the operation succeeded before the error was raised.
    "fatal_error" => "We had an issue communicating with Slack. Please try again",

    # The server could not complete your operation(s) without encountering an error, likely due to a transient issue on our end. It's possible some aspect of the operation succeeded before the error was raised.
    "internal_error" => "We had an issue communicating with Slack. Please try again",
  }

  # Don't run as a validator. This will post a message to the corresponding slack channel which is unexpected outside of a create/update flow
  def validate_and_post_message_to_slack(actor, reminder_url, reminder)
    action = new_record? ? "created" : "updated"

    success, response = Reminders::SlackApi.post_reminder_change_to_channel(
      reminder_url: reminder_url,
      reminder: reminder,
      user: actor,
      action: action,
    )

    error = response.try(:dig, "error")
    # slack integration returns a 200 even if there is an error, error is passed in a response body
    if !success || error.present?
      add_slack_error(error || "unknown error", reminder, actor, action)
      return false
    end

    reminder.slack_channel_id = response["channel"]
    reminder.display_name = response["channel_name"] if reminder.add_by_channel_id_or_name?
    true
  end

  def add_slack_error(error, reminder, actor, action)
    if msg = SLACK_ERRORS[error]
      reminder.errors.add(:slack_channel, msg % reminder.slack_channel)
    elsif reminder.add_by_channel_id_or_name?
      reminder.errors.add(:slack_channel, "We encountered issues setting up the reminder on your Slack Channel. Please try providing the channel id and ensure @github has been invited to the channel. "\
        "If this persists, please reach out to our support team.")
    else
      reminder.errors.add(:slack_channel, "We encountered issues setting up the reminder on your Slack Channel. Try again in a few moments. "\
        "If this persists, please reach out to our support team.")
    end

    GitHub.logger.error({
      "code.function" => "validate_and_post_message_to_slack",
      "exception.message" => error,
      "gh.actor.id" => actor.id,
      "gh.scheduled_reminders.action" => action
    })
  end
end
