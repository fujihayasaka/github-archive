# typed: true
# frozen_string_literal: true

module ReactionsHelper
  extend T::Helpers

  requires_ancestor { ActionView::Helpers::TagHelper }

  include EscapeHelper

  TOOLTIP_SOFT_TRUNCATION_THRESHOLD = 11
  TOOLTIP_HARD_TRUNCATION_THRESHOLD = 10

  # Public: Generate the text for a tooltip describing who posted a given
  # reaction.
  #
  # emotion - Emotion object
  # truncated_user_logins - array with the first TOOLTIP_SOFT_TRUNCATION_THRESHOLD users of the reaction group
  # total_users - total number of users on the reaction group
  # bold_usernames - Boolean, indicates if the usernames should be wrapped in <span class="text-bold">. Defaults to false.
  #
  # Returns a string (ex. "monalisa, hubot, and ghost reacted with smile emoji")
  def reaction_count_tooltip_for_model(emotion, truncated_user_logins, total_users, bold_usernames: false)
    return "" if truncated_user_logins.empty?

    is_truncated = total_users > TOOLTIP_SOFT_TRUNCATION_THRESHOLD

    names = if is_truncated
      truncated_user_logins.first(TOOLTIP_HARD_TRUNCATION_THRESHOLD)
    else
      truncated_user_logins
    end
    names = make_bold_usernames(names) if bold_usernames
    names += ["#{total_users - TOOLTIP_HARD_TRUNCATION_THRESHOLD} more"] if is_truncated

    safe_join([html_safe_to_sentence(names),
      " reacted with ", emotion.pronounceable_label, " emoji"
    ])
  end

  private

  # Internal: Wrap usernames in <span class="text-bold">
  #
  # logins - An array of logins (usernames) to get wrapped in <span>s
  #
  # Returns an array.
  def make_bold_usernames(logins)
    logins.map { |login| content_tag(:span, login, class: "text-bold") }
  end
end
