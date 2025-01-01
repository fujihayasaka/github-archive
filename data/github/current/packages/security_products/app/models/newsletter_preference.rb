# typed: true
# frozen_string_literal: true

class NewsletterPreference < ApplicationRecord::Domain::Users
  extend T::Sig

  include Instrumentation::Model

  VALID_SOURCES = %w[footer job settings okta-team-sync undefined].freeze

  belongs_to :user

  validates_presence_of :user_id
  validates_uniqueness_of :user_id

  validate :single_preference
  validate :preference_present

  after_commit :instrument_create, on: :create
  after_commit :instrument_update, on: :update

  scope :transactional, -> { where("elected_transactional_at is not null") }

  # Public: Should a user receive marketing email?
  #
  # We assume that users do not want to receive marketing email
  # from GitHub unless they have set their email preference
  # to receive marketing email.
  #
  # user - a User object
  #
  # Returns a Boolean.
  sig { params(user: T.nilable(User)).returns(T::Boolean) }
  def self.marketing?(user:)
    return false if user.nil? || user.new_record?

    preference = find_by(user_id: user.id)
    return false unless preference

    preference.elected_marketing_at.present?
  end

  # Public: Set a user's newsletter preference to
  # receive marketing/promotional email.
  #
  # user - a User object.
  # signup - Whether or not the setting is being set during initial signup. Defaults to false.
  #
  # Returns a NewsletterPreference object.
  sig { params(user: User, signup: T::Boolean, source: T.nilable(String)).returns(NewsletterPreference) }
  def self.set_to_marketing(user:, signup: false, source: "undefined")
    tags = []

    source_tag = NewsletterPreference::VALID_SOURCES.include?(source) ? source : nil

    tags << "source:#{source_tag}"

    if preference = find_by(user_id: user.id)
      preference.update(elected_marketing_at: Time.current, elected_transactional_at: nil) if preference.elected_marketing_at.nil?
      tags << "action:updated"
    else
      preference = create(user: user, elected_marketing_at: Time.current, elected_transactional_at: nil)
      tags << "action:created"
    end

    GitHub.dogstats.increment("newsletter_preference.marketing", tags: tags)

    # Users shouldn't be enrolled in MailChimp on signup until they've verified their email address.
    unless signup
      # Remove all of the user's eligible emails from the suppression list
      # and subscribe them to the MailChimp master list.
      RemoveFromSuppressionListJob.perform_later(user.id)
    end

    preference
  end

  # Public: Set a user's newsletter preference to
  # only receive transactional email.
  #
  # user - a User object.
  #
  # Returns a NewsletterPreference object.
  sig { params(user: User, source: String).returns(NewsletterPreference) }
  def self.set_to_transactional(user:, source: "undefined")
    tags = []

    source_tag = NewsletterPreference::VALID_SOURCES.include?(source) ? source : nil

    tags << "source:#{source_tag}"

    if preference = find_by(user_id: user.id)
      preference.update(elected_marketing_at: nil, elected_transactional_at: Time.current) if preference.elected_transactional_at.nil?
      tags << "action:updated"
    else
      preference = create(user: user, elected_marketing_at: nil, elected_transactional_at: Time.current)
      tags << "action:created"
    end

    GitHub.dogstats.increment("newsletter_preference.transactional", tags: tags)

    # Deactivate any existing newsletter subscriptions.
    NewsletterSubscription.unsubscribe_all(user)

    # Add all of the user's emails to the suppression list.
    AddToSuppressionListJob.perform_later(user.id)

    preference
  end

  # Public: Which preference does the user have currently?

  # Returns a String.
  sig { returns(String) }
  def name
    elected_marketing_at ? "marketing" : "transactional"
  end

  # Public: Returns if the user has marketing email opt in or "blank" if no preference is set.
  #
  # user - a User object
  #
  # Returns a Boolean or String.
  sig { params(user: T.nilable(User)).returns(T.any(T::Boolean, String)) }
  def self.marketing_preference(user:)
    return false if user.nil? || user.new_record?

    preference = find_by(user_id: user.id)
    return "blank" unless preference

    preference.elected_marketing_at.present?
  end

  private

  # Private: Validate that only one elected_at timestamp is set.
  #
  # We use the elected_marketing_at and elected_transactional_at timestamps to
  # set the user's preference to receive or not receive marketing email.
  # Only one can be set.
  sig { void }
  def single_preference
    if elected_marketing_at && elected_transactional_at
      errors.add(:base, "can only select one preference")
    end
  end

  sig { void }
  def preference_present
    unless elected_marketing_at || elected_transactional_at
      errors.add(:base, "one preference must be set")
    end
  end

  sig { void }
  def instrument_create
    instrument :create

    experiment_arm =
      case GitHub.context[:email_opt_in_experiment_arm]
      when "control"
        "OPT_IN_PLACEMENT_CONTROL"
      when "alternative"
        "OPT_IN_PLACEMENT_ALTERNATE"
      else
        GitHub.context[:email_opt_in_experiment_arm]
      end

    data = {
      user: {
        id: T.must(user).id,
        login: T.must(user).login,
        created_at: T.must(user).created_at,
        billing_plan: T.must(user).plan.name,
        spammy: T.must(user).spammy,
        type: T.must(user.class.name).upcase,
      },
      experimental_arm: experiment_arm,
      preference_choice: name,
      visitor_id: GitHub.context[:visitor_id].to_s,
      write_type: "CREATE",
    }

    GlobalInstrumenter.instrument("newsletter.preference.change", data)
  end

  sig { void }
  def instrument_update
    instrument :update

    data = {
      user: {
        id: T.must(user).id,
        login: T.must(user).login,
        created_at: T.must(user).created_at,
        billing_plan: T.must(user).plan.name,
        spammy: T.must(user).spammy,
        type: T.must(user.class.name).upcase,
      },
      preference_choice: name,
      write_type: "UPDATE",
    }

    GlobalInstrumenter.instrument("newsletter.preference.change", data)
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def event_payload
    {
      user:                     user,
      elected:                  name,
      elected_marketing_at:     elected_marketing_at,
      elected_transactional_at: elected_transactional_at,
    }
  end
end
