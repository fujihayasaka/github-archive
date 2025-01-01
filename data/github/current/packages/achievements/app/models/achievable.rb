# typed: false
# frozen_string_literal: true

require "static_asset_paths"

class Achievable
  SKIN_TONE_NAMES = {
    1 => "light",
    2 => "light-medium",
    3 => "medium",
    4 => "medium-dark",
    5 => "dark",
  }.freeze

  delegate(
    :accepted_unlocking_model_types,
    :badge_asset_path,
    :badge_asset_url,
    :rounded_badge_asset_url,
    :defined_tiers,
    :display_name,
    :enabled?,
    :feature_flag_name,
    :fetch_dynamic_unlocking_models,
    :highest_tier,
    :needs_unlocking_oid?,
    :has_dynamic_unlocking_model?,
    :skin_tone_name_at_tier,
    :slug,
    :social_card_asset_url,
    :gradient_asset_url,
    :high_resolution_asset_url,
    :tier,
    :tiers,
    :unlocking_explanation_template,
    :uses_skin_tone?,
    :background_color,
    :has_rounded_badge_variant?,
    to: :class
  )

  def self.display_name
    name.demodulize.underscore.titleize
  end

  def self.slug
    display_name.parameterize
  end

  def self.feature_flag_name
    "achievements_#{name.demodulize.underscore}".to_sym
  end

  def self.enabled?(current_user = nil)
    GitHub.flipper[feature_flag_name].enabled? ||
      GitHub.flipper[feature_flag_name].enabled?(current_user)
  end

  def self.with_slug(slug)
    BY_SLUG[slug]
  end

  def self.tiers
    0...(defined_tiers.size)
  end

  def self.highest_tier
    tiers.max
  end

  def self.known_slugs
    BY_SLUG.keys
  end

  # Public: Return the registered well-known instance of this Achievable subclass.
  def self.instance
    with_slug(slug)
  end

  # Public: Iterate over registered instances of all known Achievable subclasses.
  #
  # block - Block that will be called once with each registered Achievable subclass.
  #
  # Returns nothing.
  def self.all_known(&block)
    BY_SLUG.each_value(&block)
  end

  # Public: Return the Tier object for a given tier ordinal.
  #
  # ordinal - Integer ordinal number of one of this Achievable's defined tiers.
  #
  # Returns a Tier corresponding to the ordinal if one is defined, or a NullTier otherwise.
  def self.tier(ordinal)
    defined_tiers[ordinal] || NullTier.new(ordinal, self)
  end

  # Public: Does this Achievable's badge have different variants based on skin tone preference?
  #
  # tier - Integer tier of the Achievable to check. Some Achievable badges only have skin tone variants for their
  #   default tier's badge.
  #
  # Returns true if this Achievable has multiple skin tone variants at the current tier, false otherwise.
  def self.uses_skin_tone?(tier:)
    false
  end

  # Public: Return the name of the skin tone to be used by this Achievable's badge at the given tier.
  #
  # tier - Integer ordinal number of an Achievement's current tier.
  # tone - Integer of the user's skin tone preference, 1-5.
  #
  # Returns a String describing the skin tone to use for this Achievable's badge, or nil if the Achievable does
  # not use skin tone variants at this tier (or at all, or if the tier or tone are out of recognized range).
  def self.skin_tone_name_at_tier(tier:, tone:)
    SKIN_TONE_NAMES[tone] if uses_skin_tone?(tier: tier)
  end

  # Internal: Lazily initialize the tiers defined for a subclass.
  #
  # Returns an Array of Tier instances.
  def self.defined_tiers
    @tiers ||= []
  end

  # Internal: Call in subclasses to define the tiers for this Achievable.
  #
  # threshold - Integer describing the measurement that must be reached to earn this tier. What's being measured and
  #   compared to this threshold varies from subclass to subclass. For example, PullShark counts the number of opened
  #   pull requests, while Starstruck counts stars on a repository.
  #
  # Returns self.
  def self.define_tier(threshold: 0)
    defined_tiers << Tier.new(defined_tiers.size, threshold, self)
    self
  end

  # Internal: Call in subclasses to establish constraints on the model types that are expected to be associated with
  # associated Achievements.
  #
  # model_spec - Subclass of ::Achievable::UnlockingModelSpec that constrains the acceptable model types for
  #   associated Achievements. This may be an ::Achievable::UnlockingModelSpec::Exact that names a single class or a
  #   spec like ::Achievable::UnlockingModelSpec::Reactable to permit a defined subset of types. See
  #   app/models/achievable/unlocking_model_spec.rb for available specs.
  #
  # Returns self.
  def self.unlocking_event(model_spec:)
    @unlocking_model_spec = model_spec
    self
  end

  # Internal: Specialize `.unlocking_event` to specify a Dynamic unlocking model type. This allows us to provide the
  # dynamic model block without fighting the Ruby parser for block precedence.
  def self.dynamic_unlocking_event(model_type:, &block)
    unlocking_event(model_spec: ::Achievable::UnlockingModelSpec::Dynamic.new(model_type, &block))
  end

  # Internal: Read the unlocking explanation template set by .unlocking_event.
  #
  # locale - String indicating the locale to use for the template. Defaults to "en".
  #
  # Returns a String template.
  def self.unlocking_explanation_template(locale: "en")
    t("unlocking_event.explanation", locale: locale)
  end

  # Internal: Set the static background color associated with this Achievable. This is the hex code for the color that
  # will be used by the achievement detail view in the mobile app.
  #
  # color - String hex code for the color to use for this Achievable's background.
  def self.mobile_background_color(color = nil)
    @background_color = color
    self
  end

  # Public: Access the solid background color set with #mobile_background_color.
  #
  # Returns a String containing a six-digit hex code.
  def self.background_color
    @background_color
  end

  # Public: Determine if this achievement has a rounded badge variant asset.
  #
  # Certain achievements have a non-round badge on dotcom. In contexts where a round badge is required, we can offer
  # a rounded variant of the graphic. Override to return `true` if this is such an achievement.
  #
  # Returns `true` if this achievement has a rounded badge variant, `false` otherwise.
  def self.has_rounded_badge_variant?
    false
  end

  # Public: Return an Array<String> describing the set of acceptable model class names for associated Achievements.
  def self.accepted_unlocking_model_types
    @unlocking_model_spec.accepted_types
  end

  # Public: Return true if associated Achievements must also populate :unlocking_oid with a non-nil value.
  def self.needs_unlocking_oid?
    @unlocking_model_spec.expects_oid?
  end

  # Public: Return true if associated Achievements have an unlocking model derived at first access as opposed to
  # a relation persisted in the database.
  def self.has_dynamic_unlocking_model?
    @unlocking_model_spec.dynamic?
  end

  # Public: Use a configured block to derive dynamic unlocking models for a batch of achievements. Returns `{}` if
  # this achievable does not use a dynamic unlocking model.
  def self.fetch_dynamic_unlocking_models(*args)
    @unlocking_model_spec.fetch_dynamic_unlocking_models(*args)
  end

  def self.t(key, locale: nil)
    I18n.t(key, scope: "achievements.achievable.#{name.demodulize.underscore}", locale: locale)
  end

  def self.asset_path(*rest)
    StaticAssetPaths.fingerprinted_asset(["images/modules/profile/achievements", *rest].join("/"))
  end

  def self.asset_url(*rest)
    StaticAssetPaths.static_asset_path(asset_path(*rest))
  end

  def self.badge_filename(tier: 0, skin_tone_block: -> { 0 })
    filename_parts = [slug, tier(tier).name]

    if uses_skin_tone?(tier: tier)
      skin_tone = skin_tone_block.call
      tone_name = skin_tone_name_at_tier(tier: tier, tone: skin_tone)

      if tone_name
        filename_parts << "-#{tone_name}"
      end
    end

    "#{filename_parts.join("-")}.png"
  end

  def self.badge_asset_path(tier: 0, skin_tone_block: -> { 0 })
    asset_path(badge_filename(tier:, skin_tone_block:))
  end

  def self.badge_asset_url(tier: 0, skin_tone_block: -> { 0 })
    asset_url(badge_filename(tier:, skin_tone_block:))
  end

  def self.gradient_asset_url
    StaticAssetPaths.static_asset_path("/images/modules/profile/achievements/gradients/#{slug}-detail.png")
  end

  def self.social_card_asset_url(tier:, skin_tone_block: -> { 0 })
    asset_url("social-cards", badge_filename(tier:, skin_tone_block:))
  end

  def self.high_resolution_asset_url(skin_tone_block: -> { 0 })
    filename_parts = [slug]

    if uses_skin_tone?(tier: 0)
      skin_tone = skin_tone_block.call
      tone_name = skin_tone_name_at_tier(tier: 0, tone: skin_tone)

      if tone_name
        filename_parts << "-#{tone_name}"
      end
    end

    asset_url("high-resolution", "#{filename_parts.join("-")}.png")
  end

  def self.rounded_badge_asset_url
    asset_url("rounded", "#{slug}.png")
  end

  class Tier
    NAMES = %w(default bronze silver gold crystal).freeze

    def initialize(index, threshold, achievable_class)
      @index = index
      @threshold = threshold
      @achievable_class = achievable_class
    end

    attr_reader :index, :threshold

    def name
      NAMES[index]
    end

    def valid?
      true
    end

    def description_template(locale: "en")
      @achievable_class.t("tier_#{index}.description", locale: locale)
    end
  end

  class NullTier < Tier
    def initialize(index, achievable_class)
      super(index, 0, achievable_class)
    end

    def valid?
      false
    end

    def description_template(locale: "en")
      "Whoops! Invalid tier for this achievement."
    end
  end

  ACHIEVABLES = [
    Achievable::ArcticCodeVaultContributor,
    Achievable::DustBunny,
    Achievable::GalaxyBrain,
    Achievable::Heartbreaker,
    Achievable::HeartOnYourSleeve,
    Achievable::Mars2020Contributor,
    Achievable::OpenSourcerer,
    Achievable::PairExtraordinaire,
    Achievable::Polyglot,
    Achievable::ProximaPioneer,
    Achievable::ProximaStaffshipper,
    Achievable::ProximaStaffuser,
    Achievable::ProximaShipper,
    Achievable::ProximaPrivateGa,
    Achievable::ProximaPublicGa,
    Achievable::PublicSponsor,
    Achievable::PullShark,
    Achievable::Quickdraw,
    Achievable::Starstruck,
    Achievable::Yolo,
  ].freeze
  BY_SLUG = {}
  ACHIEVABLES.each do |subclass|
    instance = subclass.new
    BY_SLUG[instance.slug] = instance
  end
  BY_SLUG.freeze
end
