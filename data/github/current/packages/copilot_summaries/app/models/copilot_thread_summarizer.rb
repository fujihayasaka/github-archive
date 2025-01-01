# typed: strict
# frozen_string_literal: true

class CopilotThreadSummarizer
  extend GitHub::ResilienceMixin

  MIN_CHAR_COUNT_FOR_SUMMARIZING = 1000

  # Public: Check whether a thread with the provided attributes can be summarized by Copilot for the specified viewer.
  #
  # viewer - the authenticated user who is viewing the content to be summarized
  # body_length - total characters in the main body of the content to be summarized; used to determine whether the
  #               content is long enough that offering summarization makes sense
  # get_comment_bodies_length - an optional lambda that should return the total characters in the bodies of comments
  #                             shown in the thread of the content to be summarized; used when the `body_length` alone
  #                             is not long enough to summarize
  # copilot_user - optional Copilot user for checking access, if one is already available; will be constructed
  #                for the `viewer` if omitted
  sig do
    params(
      viewer: T.nilable(User),
      body_length: Integer,
      copilot_user: T.nilable(T.any(Copilot::Public::User, Copilot::User)),
      get_comment_bodies_length: T.nilable(T.proc.returns(Integer))
    ).returns(T::Boolean)
  end
  def self.can_be_summarized?(viewer:, body_length:, copilot_user: nil, get_comment_bodies_length: nil)
    return false unless viewer
    unless thread_meets_minimum_length?(
      body_length: body_length,
      get_comment_bodies_length: get_comment_bodies_length,
    )
      return false
    end
    has_copilot_summaries_access?(viewer: viewer, copilot_user: copilot_user)
  end

  sig do
    params(
      viewer: T.nilable(User),
      copilot_user: T.nilable(T.any(Copilot::Public::User, Copilot::User))
    ).returns(T::Boolean)
  end
  def self.has_copilot_summaries_access?(viewer:, copilot_user: nil)
    return false unless viewer

    copilot_user ||= Copilot::Public::User.new(viewer)

    with_database_error_fallback(fallback: false) do
      # If we've publicly shipped the summaries feature, any level of Copilot access is sufficient:
      return true if viewer.feature_enabled?(:copilot_summary_ga) && copilot_user.has_copilot_access?

      # If we haven't publicly shipped Copilot summaries...
      if copilot_user.has_ce_access? || copilot_user.has_cb_access?
        # Copilot Enterprise and Copilot Business users need access to beta features:
        copilot_user.beta_features_github_chat_enabled?
      else
        # Otherwise Copilot Individual access is sufficient:
        copilot_user.has_ci_access?
      end
    end
  end

  sig do
    params(
      body_length: Integer,
      get_comment_bodies_length: T.nilable(T.proc.returns(Integer))
    ).returns(T::Boolean)
  end
  def self.thread_meets_minimum_length?(body_length:, get_comment_bodies_length: nil)
    return true if body_length >= MIN_CHAR_COUNT_FOR_SUMMARIZING

    # Don't load comments in the thread until we know the body alone doesn't meet minimum length requirements.
    comment_bodies_length = get_comment_bodies_length&.call || 0
    body_length + comment_bodies_length >= MIN_CHAR_COUNT_FOR_SUMMARIZING
  end
  private_class_method :thread_meets_minimum_length?
end
