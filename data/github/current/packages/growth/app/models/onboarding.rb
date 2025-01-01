# typed: strict
# frozen_string_literal: true

# Records various onboarding events that occur for a User.
#
# Check if a user has completed a specific onboarding event:
#   Onboarding.for(user).enrolled_in_welcome_series?
#
# Complete an onboarding event for a user:
#   Onboarding.for(user).enrolled_in_welcome_series!
#
class Onboarding
  class OnboardingError < StandardError; end

  sig { params(user: User).void }
  def initialize(user)
    @user = user
  end

  # Public: Instantiates a new Onboarding object for a user.
  # Returns an Onboarding object.
  sig { params(user: User).returns(Onboarding) }
  def self.for(user)
    new(user)
  end

  sig { returns(String) }
  def inspect
    "#<Onboarding @user=#<User id:#{user.id}, login:#{user.login}>>"
  end

  # Public: Has the user been enrolled in the
  # welcome email series in MailChimp?
  #
  # Returns a Boolean.
  sig { returns(T::Boolean) }
  def enrolled_in_welcome_series?
    completed_event?("enrolled_in_welcome_series")
  end

  # Public: Record that the user has been
  # enrolled in the welcome series.
  #
  # Returns GitHub::Result with the error if the event has already been recorded
  # for the user, and a GitHub::Result with Onboarding::Event object otherwise.
  sig { returns(GitHub::Result) }
  def enrolled_in_welcome_series!
    return GitHub::Result.error(OnboardingError.new("already enrolled in welcome series")) if enrolled_in_welcome_series?
    complete_event("enrolled_in_welcome_series")
  end

  # Public: Whether or not the user been sent the welcome
  # email from AccountMailer#welcome
  #
  # Returns a Boolean.
  sig { returns(T::Boolean) }
  def welcomed_via_email?
    completed_event?("welcomed_via_email")
  end

  # Public: Record that the user has been
  # sent a welcome email via AccountMailer#welcome
  #
  # Returns GitHub::Result with the error if the event has already been recorded
  # for the user, and a GitHub::Result with Onboarding::Event object otherwise.
  sig { returns(GitHub::Result) }
  def welcomed_via_email!
    return GitHub::Result.error(OnboardingError.new("already welcomed via email")) if welcomed_via_email?
    complete_event("welcomed_via_email")
  end

  # Public: Whether or not the user has answered
  # a set of user identification questions.
  #
  # Returns a Boolean.
  sig { returns(T::Boolean) }
  def answered_user_identification_questions?
    completed_event?("answered_user_identification_questions")
  end

  # Public: Record that the user has answered the
  # user identification questions.
  #
  # Returns GitHub::Result with the error if the event has already been recorded
  # for the user, and a GitHub::Result with Onboarding::Event object otherwise.
  sig { returns(GitHub::Result) }
  def answered_user_identification_questions!
    return GitHub::Result.error(OnboardingError.new("already answered user identification questions")) if answered_user_identification_questions?
    complete_event("answered_user_identification_questions")
  end

  # Public: Has the user been enrolled in the
  # team admin onboarding email series in MailChimp?
  #
  # Returns a Boolean.
  sig { returns(T::Boolean) }
  def enrolled_in_team_admin_onboarding_series?
    completed_event?("enrolled_in_team_admin_onboarding_series")
  end

  # Public: Record that the user has been
  # enrolled in  the team admin onboarding email series.
  #
  # Returns GitHub::Result with the error if the event has already been recorded
  # for the user, and a GitHub::Result with Onboarding::Event object otherwise.
  sig { returns(GitHub::Result) }
  def enrolled_in_team_admin_onboarding_series!
    return GitHub::Result.error(OnboardingError.new("already enrolled in welcome series")) if enrolled_in_welcome_series?
    complete_event("enrolled_in_team_admin_onboarding_series")
  end

  private

  sig { returns(User) }
  attr_reader :user

  # Private: Record the completion of a
  # specific onboarding event.
  sig { params(event_name: String).returns(GitHub::Result) }
  def complete_event(event_name)
    event = Onboarding::Event.create!(user: user, name: event_name)
    GitHub.dogstats.increment("onboarding", tags: ["event:#{event_name}", "action:completed"])
    GitHub::Result.new { event }
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => error
    GitHub::Result.error(error)
  end

  # Private: Whether or not the given event exists for the user.
  # Returns a Boolean.
  sig { params(event_name: String).returns(T::Boolean) }
  def completed_event?(event_name)
    Onboarding::Event.where(
      user_id: user.id,
      name: event_name,
    ).exists?
  end
end
