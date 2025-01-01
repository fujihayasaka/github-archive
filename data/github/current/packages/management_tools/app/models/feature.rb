# typed: true
# frozen_string_literal: true

class Feature < ApplicationRecord::Collab
  include Instrumentation::Model
  include GitHub::Relay::GlobalIdentification
  include GitHub::Validations

  FLIPPER_CACHE_KEY = "prerelease_features:flipper_feature_ids".freeze
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
    flipper_feature_id
    image_link
    documentation_link
  ]

  belongs_to :flipper_feature
  has_many :user_seen_features
  destroy_dependents_in_background :user_seen_features

  has_many :enrollments, class_name: "FeatureEnrollment"
  destroy_dependents_in_background :enrollments

  after_commit :instrument_create, on: :create
  after_commit :instrument_deletion, on: :destroy
  after_commit :instrument_update, on: :update
  before_save :set_flipper_feature_name

  validates :public_name, presence: true, unicode3: true
  validates :public_name, uniqueness: { case_sensitive: false }, if: -> { T.bind(self, Feature); errors[:public_name].blank? }
  validates :flipper_feature, uniqueness: { allow_nil: true }
  validates :slug, presence: true,
    format: { with: /\A[a-z0-9_-]+\z/i }
  validates :slug, uniqueness: { case_sensitive: false }, if: -> { T.bind(self, Feature); errors[:slug].blank? }
  validates :feedback_link, presence: true

  after_commit :bust_flipper_id_cache, if: -> { T.bind(self, Feature); prerelease? || flipper_feature_id_changed? }

  scope :prerelease, -> { where.not(flipper_feature: nil) }
  scope :without_flipper, -> { where(flipper_feature_id: nil) }

  scope :flipper_enabled_for, -> (user) {
    GitHub.dogstats.distribution_time("feature_preview.scope_latency", tags: ["scope:flipper_enabled_for"]) do
      # query on mysql1
      enabled_flipper_features = FlipperFeature.where(id: flipper_feature_ids)
        .fully_enabled_or_enabled_for_actor(user)
        .pluck(:id)

      # query on collab
      where(flipper_feature_id: enabled_flipper_features)
    end
  }

  scope :available_to, -> (user) {
    GitHub.dogstats.distribution_time("feature_preview.scope_latency", tags: ["scope:available_to"]) do
      flipper_enabled_for(user).or(without_flipper)
    end
  }

  scope :published, -> {
    where.not(published_at: nil)
  }

  scope :unseen_by, -> (user) {
    where.not(id: user.user_seen_features.select(:feature_id))
  }

  # Public: Returns all flipper feature IDs associated with prerelease Features.
  # This is used to filter the flipper_feature records when determining which
  # Features a User has access to.
  #
  # Returns an Array of Integer IDs
  def self.flipper_feature_ids
    ids = FeatureManagement::Kv.store.get(FLIPPER_CACHE_KEY).value!

    if ids
      ids.split(",").map(&:to_i)
    else
      flipper_feature_ids!
    end
  end

  # Public: Regenerates and returns the list of flipper feature IDs associated
  # with Features.
  #
  # Returns an Array of Integer IDs
  def self.flipper_feature_ids!
    ids = prerelease.pluck(:flipper_feature_id)
    ActiveRecord::Base.connected_to(role: :writing) do
      GitHub.dogstats.count("feature_preview.prerelease_feature_count", ids.size)
      FeatureManagement::Kv.store.set(FLIPPER_CACHE_KEY, ids.join(","))
    end
    ids
  end

  # Public: Enrolls a User in this Feature.
  #
  # enrollee - the User to enroll
  #
  # Returns a FeatureEnrollment if successful, false otherwise
  def enroll(enrollee)
    return false unless flipper_enabled?(enrollee)

    GitHub.dogstats.increment("feature_preview.enrolled", tags: ["feature:#{slug}", "default:#{enrolled_by_default ? 'enrolled' : 'unenrolled'}", "prerelease:#{prerelease?}"])
    FeatureEnrollment.set_for(feature: self, enrollee: enrollee, enrolled: true)
  end

  # Public: Unenrolls a User from this Feature.
  #
  # enrollee - the User to unenroll
  #
  # Returns a FeatureEnrollment if successful, false otherwise
  def unenroll(enrollee)
    return false unless flipper_enabled?(enrollee)

    GitHub.dogstats.increment("feature_preview.unenrolled", tags: ["feature:#{slug}", "default:#{enrolled_by_default ? 'enrolled' : 'unenrolled'}", "prerelease:#{prerelease?}"])
    FeatureEnrollment.set_for(feature: self, enrollee: enrollee, enrolled: false)
  end

  def enrolled?(enrollee)
    return false unless flipper_enabled?(enrollee)

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
    !!flipper_feature_id
  end

  def to_s
    slug
  end
  alias_method :to_param, :to_s

  def async_viewer_can_read?(viewer)
    async_flipper_enabled?(viewer)
  end

  def viewer_can_read?(viewer)
    flipper_enabled?(viewer)
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

  def flipper_enabled?(user)
    if flipper_feature_name.present?
      GitHub.flipper[T.unsafe(flipper_feature_name).to_sym].enabled?(user)
    elsif flipper_feature
      T.unsafe(flipper_feature).enabled?(user)
    else
      true
    end
  end

  def async_flipper_enabled?(user)
    async_flipper_feature.then do |flipper_feature|
      if flipper_feature
        flipper_feature.enabled?(user)
      else
        true
      end
    end
  end

  def set_flipper_feature_name
    self.flipper_feature_name = flipper_feature&.name
  end

  # Private: Clear the flipper feature ID cache. This runs in a callback after
  # a Feature is created, updated, or destroyed.
  def bust_flipper_id_cache
    FeatureManagement::Kv.store.del(FLIPPER_CACHE_KEY)
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
      feature_flag: flipper_feature&.name,
      published_at: published_at,
      feedback_link: feedback_link,
    }
  end

  def event_prefix
    :toggleable_feature
  end
end
