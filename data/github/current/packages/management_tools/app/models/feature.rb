# typed: true
# frozen_string_literal: true

class Feature < ApplicationRecord::Collab
  self.ignored_columns = %w(flipper_feature_id)

  include Instrumentation::Model
  include GitHub::Relay::GlobalIdentification
  include GitHub::Validations

  FEEDBACK_HOST = "support.github.com"
  FEEDBACK_PATH = "/contact/feedback"
  FEEDBACK_PARAMS = { "contact[subject]": "Product feedback" }

  # This is the list of fields we want to track changes of in the audit log
  AUDIT_LOG_UPDATE_FIELDS = %w[
    public_name
    slug
    description
    published_at
    enrolled_by_default
    feedback_link
    feature_flag_name
    image_link
    documentation_link
  ]

  has_many :user_seen_features
  destroy_dependents_in_background :user_seen_features

  has_many :enrollments, class_name: "FeatureEnrollment"
  destroy_dependents_in_background :enrollments

  after_commit :instrument_create, on: :create
  after_commit :instrument_deletion, on: :destroy
  after_commit :instrument_update, on: :update

  validates :public_name, presence: true, unicode3: true
  validates :public_name, uniqueness: { case_sensitive: false }, if: -> { T.bind(self, Feature); errors[:public_name].blank? }
  validates :slug, presence: true,
    format: { with: /\A[a-z0-9_-]+\z/i }
  validates :slug, uniqueness: { case_sensitive: false }, if: -> { T.bind(self, Feature); errors[:slug].blank? }
  validates :feedback_link, presence: true
  validates :feature_flag_name, uniqueness: { allow_nil: true }
  validate :feature_flag_name_exists, if: -> { T.bind(self, Feature); feature_flag_name.present? }

  alias_attribute :feature_flag_name, :flipper_feature_name

  scope :prerelease, -> {
    GitHub.dogstats.distribution_time("feature_preview.scope_latency", tags: ["scope:prerelease"]) do
      where.not(feature_flag_name: nil)
    end
  }

  scope :without_feature_flag, -> {
    GitHub.dogstats.distribution_time("feature_preview.scope_latency", tags: ["scope:without_feature_flag"]) do
      where(feature_flag_name: nil)
    end
  }

  scope :feature_flag_enabled_for, -> (user) {
    GitHub.dogstats.distribution_time("feature_preview.scope_latency", tags: ["scope:feature_flag_enabled_for"]) do
      where(feature_flag_name: prerelease.pluck(:feature_flag_name).select { |name| FeatureFlag.vexi.enabled?(T.unsafe(name).to_sym, user, default: false) })
    end
  }

  scope :available_to, -> (user) {
    GitHub.dogstats.distribution_time("feature_preview.scope_latency", tags: ["scope:available_to"]) do
      feature_flag_enabled_for(user).or(without_feature_flag)
    end
  }

  scope :published, -> {
    GitHub.dogstats.distribution_time("feature_preview.scope_latency", tags: ["scope:published"]) do
      where.not(published_at: nil)
    end
  }

  scope :unseen_by, -> (user) {
    GitHub.dogstats.distribution_time("feature_preview.scope_latency", tags: ["scope:unseen_by"]) do
      where.not(id: user.user_seen_features.select(:feature_id))
    end
  }

  # Public: Enrolls a User in this Feature.
  #
  # enrollee - the User to enroll
  #
  # Returns a FeatureEnrollment if successful, false otherwise
  def enroll(enrollee)
    return false unless feature_flag_enabled?(enrollee)

    GitHub.dogstats.increment("feature_preview.enrolled", tags: ["feature:#{slug}", "default:#{enrolled_by_default ? 'enrolled' : 'unenrolled'}", "prerelease:#{prerelease?}"])
    FeatureEnrollment.set_for(feature: self, enrollee: enrollee, enrolled: true)
  end

  # Public: Unenrolls a User from this Feature.
  #
  # enrollee - the User to unenroll
  #
  # Returns a FeatureEnrollment if successful, false otherwise
  def unenroll(enrollee)
    return false unless feature_flag_enabled?(enrollee)

    GitHub.dogstats.increment("feature_preview.unenrolled", tags: ["feature:#{slug}", "default:#{enrolled_by_default ? 'enrolled' : 'unenrolled'}", "prerelease:#{prerelease?}"])
    FeatureEnrollment.set_for(feature: self, enrollee: enrollee, enrolled: false)
  end

  def enrolled?(enrollee)
    return false unless feature_flag_enabled?(enrollee)

    enrollment = ActiveRecord::Base.connected_to(role: :reading) do
      enrollments.find_by(enrollee: enrollee)
    end

    if enrollment
      enrollment.enrolled?
    else
      enrolled_by_default?
    end
  end

  # Public: Whether this Feature is in a prerelease stage. When this is true,
  # it will appear in the top-level feature preview menu.
  #
  # Returns a Boolean
  def prerelease?
    !!feature_flag_name
  end

  def to_s
    slug
  end
  alias_method :to_param, :to_s

  def async_viewer_can_read?(viewer)
    feature_flag_enabled?(viewer)
  end

  def viewer_can_read?(viewer)
    feature_flag_enabled?(viewer)
  end

  def can_enroll?(enroller:, enrollee:)
    enroller == enrollee
  end

  def event_context(prefix: :toggleable_feature)
    {
      prefix => public_name,
      "#{prefix}_id".to_sym => id,
    }
  end

  def platform_type_name
    "ToggleableFeature"
  end

  def self.default_feedback_link
    URI::HTTPS.build(host: FEEDBACK_HOST, path: FEEDBACK_PATH, query: URI.encode_www_form(FEEDBACK_PARAMS)).to_s
  end

  def enrolled_by_default
    # Used when testing on the TEST_ALL_FEATURES build
    return true if GitHub.beta_features_enrolled_by_default?

    self[:enrolled_by_default]
  end

  def description
    return unless self[:description]
    self[:description].dup.force_encoding(::Encoding::UTF_8).scrub!
  end

  private

  def feature_flag_enabled?(user)
    if feature_flag_name.present?
      FeatureFlag.vexi.enabled_or_raise?(T.unsafe(feature_flag_name).to_sym, user) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
    else
      true
    end
  end

  def feature_flag_name_exists
    return if feature_flag_name.blank?

    unless FeatureFlag.vexi.exists_or_raise?(feature_flag_name) # rubocop:disable GitHub/FeatureManagement/NoVexiNonStandardUsage
      errors.add(:feature_flag_name, "does not exist")
    end
  end

  def instrument_create
    instrument :create, serialized_feature
  end

  def instrument_deletion
    instrument :destroy, serialized_feature
  end

  def instrument_update
    payload = {}

    AUDIT_LOG_UPDATE_FIELDS.each do |field|
      next unless previous_changes.has_key?(field)

      payload["#{field}_was"], payload[field] = previous_changes[field]
    end

    instrument :update, payload
  end

  # Internal: event payload for Instrumentation
  def event_payload
    {
      event_prefix => self,
    }
  end

  def serialized_feature
    {
      slug: slug,
      description: description,
      image_link: image_link,
      documentation_link: documentation_link,
      enrolled_by_default: enrolled_by_default?,
      feature_flag: feature_flag_name,
      published_at: published_at,
      feedback_link: feedback_link,
    }
  end

  def event_prefix
    :toggleable_feature
  end
end
