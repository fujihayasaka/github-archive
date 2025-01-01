# rubocop:disable GitHub/FeatureManagement/NoFlipperFeatureUsage
# typed: true
# frozen_string_literal: true

class FlipperFeature < ApplicationRecord::Domain::Features
  include Instrumentation::Model
  extend Flipper::ConcurrencyProxy

  GITHUB_ORG_ID = 9919
  BIG_FEATURE_WARNING_THRESHOLD = 100
  GITHUB_SERVICE_NAME = "github" # no flipper feature should belong to this service
  PREVIEW_FEATURES_GROUP_NAME = "preview_features"

  # Enum used for indicating what stamps a feature flag change should be propagted to
  enum :rollout_tree, {
    unset: nil,
    dotcom_only: 0,
    dotcom_and_proxima: 1
  }, prefix: true

  validates :name, presence: true,
    format: { with: /\A[a-z0-9_-]+\z/i }
  validates :tracking_issue_url, presence: true, if: -> { !Rails.env.development? },
    format: {
      with: /\Ahttps:\/\/(github\.com|github\.ghe\.com)\/.*\z/i,
      message: "must start with https://github.com/ or https://github.ghe.com/"
    }

  validates :name, uniqueness: { case_sensitive: false }, if: -> { T.bind(self, FlipperFeature); errors[:name].blank? }
  validates :service_name, presence: true, if: -> { GitHub::ServiceCatalog.enabled? }
  validates :service_name, exclusion: {
    in: [GITHUB_SERVICE_NAME],
    message: "may not be the generic 'github' service"
  }
  validate :name_byte_size

  attribute :description, StringFromBinary.new
  attribute :exclusion_rule, :integer, default: nil

  has_one :feature
  has_many :flipper_gates
  destroy_dependents_in_background :flipper_gates
  belongs_to :github_org_team, class_name: "Team"

  after_commit :instrument_create, on: :create
  after_commit :instrument_update, on: :update
  after_commit :instrument_deletion, on: :destroy
  after_destroy :cleanup_raw_feature

  # From Flipper::ConcurrencyProxy module, wraps methods and check if concurrency validation is enabled
  # and will set properties on the Flipper::Feature that are used in flipper mysql adapter
  rollout_updated_at_proxy :enable, :disable, :enable_group, :disable_group,
    :enable_percentage_of_actors, :disable_percentage_of_actors,
    :enable_percentage_of_time, :disable_percentage_of_time

  PERCENTAGES = [0, 1, 5, 10, 25, 50, 75, 100].freeze

  delegate :state, :on?, :off?, :conditional?, :enabled?,
    :enable, :disable, :enable_group, :disable_group, :groups_value,
    :enable_percentage_of_actors, :disable_percentage_of_actors,
    :enable_percentage_of_time, :disable_percentage_of_time,
    :percentage_of_time_value, :percentage_of_actors_value,
    :actors_value, :boolean_value, :gate, to: :raw_feature

  scope :by_name, -> { order("name ASC") }

  scope :matches_name_or_description, -> (query) do
    if query.present?
      sanitized_query = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
      where("#{table_name}.name LIKE ? OR #{table_name}.description LIKE ?", sanitized_query,
            sanitized_query)
    else
      scoped
    end
  end

  # Public: determines which features are fully enabled. This includes features
  # where any of the below are true
  #
  # * the boolean gate is true or 1
  # * the percentage of time gate is 100
  # * the percentage of actors gate is 100
  #
  # Returns an ActiveRecord::Relation
  scope :fully_enabled, -> {
    query_parts = {
      "(flipper_gates.name = :boolean_name AND (flipper_gates.value = :boolean_value OR flipper_gates.value = :integer_value))": { boolean_name: "boolean", boolean_value: "true", integer_value: "1" },
      "flipper_gates.name IN (:percentile_name) AND CAST(flipper_gates.value AS decimal(5,2)) = :percentile_value": { percentile_name: FlipperGate::PERCENTAGE_TYPES, percentile_value: 100.0 },
    }

    joins(:flipper_gates).where(query_parts.keys.join(" OR "), query_parts.values.reduce({}, :merge))
  }

  # Public: determines which features are fully disabled. This includes features
  # where all of the below are true
  #
  # * the boolean gate is false
  # * the percentage of time gate is 0
  # * the percentage of actors gate is 0
  # * no gate yet exists for the feature
  #
  # Returns an ActiveRecord::Relation
  scope :fully_disabled, -> {
    query_parts = {
      "flipper_gates.name = :boolean_name AND flipper_gates.value = :boolean_value": { boolean_name: "boolean", boolean_value: "false" },
      "flipper_gates.name IN (:percentile_name) AND CAST(flipper_gates.value AS decimal(5,2)) = :percentile_value": { percentile_name: FlipperGate::PERCENTAGE_TYPES, percentile_value: 0.0 },
    }

    left_outer_joins(:flipper_gates)
      .where(query_parts.keys.join(" OR "), query_parts.values.reduce({}, :merge))
      .or(where(flipper_gates: { id: nil })) # not having a gate is the same as being fully disabled
  }

  # Public: determines which features are staff shipped, i.e. enabled for the
  # preview_features group.
  #
  # Returns an ActiveRecord::Relation
  scope :staff_shipped, -> {
    joins(:flipper_gates)
      .where(flipper_gates: { name: "groups", value: PREVIEW_FEATURES_GROUP_NAME })
  }

  # Public: determines which features are partially shipped, i.e. enabled for
  # a subset of actors or via a non-zero, non-100 percentage gate,
  # or for a group other than preview_features.
  #
  # Returns an ActiveRecord::Relation
  scope :actor_or_percentage, -> {
    query_parts = {
      "flipper_gates.name = :actors_name": { actors_name: "actors" },
      "flipper_gates.name IN (:percentile_name) AND CAST(flipper_gates.value AS decimal(5,2)) BETWEEN :percentile_value_zero AND :percentile_value_hundred":
      { percentile_name: FlipperGate::PERCENTAGE_TYPES, percentile_value_zero: 0.01, percentile_value_hundred: 99.99 }, # BETWEEN is inclusive so we use 1/99 instead of 0/100
      "flipper_gates.name = :groups_name AND flipper_gates.value != :value": { groups_name: "groups", value: PREVIEW_FEATURES_GROUP_NAME },
    }

    joins(:flipper_gates).where(query_parts.keys.join(" OR "), query_parts.values.reduce({}, :merge))
  }

  # Public: Find all flipper features turned on for a given actor.
  #
  # actor - a User
  # limit - how many FlipperFeatures to evaluate before truncating results
  scope :fully_enabled_or_enabled_for_actor, -> (actor, limit: 30) {
    # This scope results in N+1 additional queries, so applying a limit reduces
    # the potential impact.
    possible_results = self.limit(limit)

    filtered_results = possible_results.select do |feature|
      feature.fully_enabled? || feature.always_enabled?(actor)
    end

    possible_results.to_a == filtered_results ? possible_results : where(id: filtered_results)
  }

  scope :updated_since, -> (last_updated_at, big_features = []) {
    where("rollout_updated_at > ?", last_updated_at).where.not(name: big_features)
  }

  # Public: returns a relation where the rollout_updated_at lands between the
  # given times. If a falsey value is passed in for either starts or ends, it
  # will fall back to a default value.
  #
  # If no starts _and_ no ends are passed in, return the current relation.
  #
  # starts - a string that Time.parse can parse (hopefully) or nil
  # ends - a string that Time.parse can parse (hopefully) or nil
  #
  # Returns an ActiveRecord::Relation
  scope :updated_between, -> (starts, ends) do
    return if starts.blank? && ends.blank?

    safe_starts = safe_parse_time(starts) || Time.new(2000) # all rollout_updated_at values would be after this time.
    safe_ends = safe_parse_time(ends) || Time.current
    where("rollout_updated_at BETWEEN ? AND ?", safe_starts, safe_ends)
  end

  # Public: returns a relation where the service_name is LIKE the passed in name
  #
  # If comma-separated names are passed in, it will return a relation where the
  # service name matches with an OR clause.
  #
  # name - a String of comma-separated service names
  #
  # Returns an ActiveRecord::Relation
  scope :service_name_like, -> (names) do
    return unless names.present?

    name, *rest = names.split(",").map(&:strip)
    scope = with_substring("service_name", name)
    rest.each { scope = scope.or(with_substring("service_name", _1)) }
    scope
  end

  scope :without_big_features, -> (big_features) {
    where.not(name: big_features)
  }

  class << self
    # Internal: attempts to parse the passed in argument as a Time object. If
    # that fails, return nil instead of raising.
    #
    # Returns a Time object or NilClass
    def safe_parse_time(maybe_parseable)
      return unless maybe_parseable
      Time.parse(maybe_parseable)
    rescue ArgumentError
      nil
    end

    private

    def find_or_create_by(*)
      super
    end

    def find_or_create_by!(*)
      super
    end
  end

  # Takes a payload of data from an audit log entry and determines the string
  # label to use for the subject.
  def self.get_subject_label(gate_name:, subject:, skip_actor_gates: false)
    return nil if gate_name == :actor && skip_actor_gates

    case gate_name
    when :boolean then "everyone"
    when :percentage_of_time then "#{subject}% of enabled? calls"
    when :percentage_of_actors then "#{subject}% of actors"
    when :group then "the #{subject} group"
    when nil then "everyone"
    else subject
    end
  end

  # Public: returns a flipper features that are fully enabled, i.e. boolean
  # gates set to true or percentage gates set to 100, batch loaded.
  #
  # Returns a Hash of { FlipperFeature => Boolean }
  batch_method(:prelude_fully_enabled?) do |features|
    feature_ids = features.map(&:id)
    enabled = FlipperFeature.where(id: feature_ids).fully_enabled.distinct.pluck(:id)
    features.each_with_object({}) do |feature, hash|
      hash[feature] = enabled.include?(feature.id)
    end
  end

  # Public: returns a flipper features that are staff shipped, i.e.
  # preview_features group enabled, batch loaded.
  #
  # Returns a Hash of { FlipperFeature => Boolean }
  batch_method(:prelude_staff_shipped?) do |features|
    feature_ids = features.map(&:id)
    staff_shipped = FlipperFeature.where(id: feature_ids).staff_shipped.distinct.pluck(:id)
    features.each_with_object({}) do |feature, hash|
      hash[feature] = staff_shipped.include?(feature.id)
    end
  end

  # Public: returns a flipper features that are have actor or percentage gates,
  # i.e. actor or PERCENTAGE_TYPES gate enabled, batch loaded.
  #
  # Returns a Hash of { FlipperFeature => Boolean }
  batch_method(:prelude_actor_or_percentage?) do |features|
    feature_ids = features.map(&:id)
    actor_or_percentage = FlipperFeature.where(id: feature_ids).actor_or_percentage.distinct.pluck(:id)
    features.each_with_object({}) do |feature, hash|
      hash[feature] = actor_or_percentage.include?(feature.id) && !feature.groups_value.include?(PREVIEW_FEATURES_GROUP_NAME)
    end
  end

  def global_id
    name
  end

  # Public: the Set of Flipper::Types::Groups that are not enabled for this feature
  def available_groups
    raw_feature.disabled_groups
  end

  # Public: The loaded actor instances which have access to the feature.
  #
  # Returns Array of mixed types
  def actors
    @actors ||= actor_ids_by_class.flat_map do |actor_class, ids|
      if actor_class.is_a?(String)
        # Class could not be constantized
        []
      elsif actor_class < ActiveRecord::Base
        scope = if [User, Organization].include?(actor_class)
          actor_class.includes(:profile)
        elsif actor_class == Repository
          actor_class.includes(:owner)
        else
          actor_class
        end
        scope.where(id: ids)
      else
        ids.map do |id|
          if actor_class.respond_to? :find_by_id
            actor_class.find_by_id(id)
          else
            actor_class.new(id)
          end
        end
      end
    end
  end

  def current_visitor_actors_value
    @current_visitor_actors_value ||= Set.new(actors_value.select do |actor|
      GitHub::FlipperActor.class_name_from_flipper_id(actor) == User::CurrentVisitorActor.name
    end)
  end

  # Public: Use the name of the feature when constructing URLs
  def to_param
    name
  end

  # Public: Determines if a percentage of actors has been set outside of
  # expected percentages defined in PERCENTAGES.
  #
  # Returns true if custom percentage is used, false if not.
  def custom_actor_percentage?
    !PERCENTAGES.include?(percentage_of_actors_value)
  end

  # Public: Determines if a percentage of random has been set outside of
  # expected percentages defined in PERCENTAGES.
  #
  # Returns true if custom percentage is used, false if not.
  def custom_random_percentage?
    !PERCENTAGES.include?(percentage_of_time_value)
  end

  def code_usage
    feature_name_in_code = name.underscore
    @code_usage ||= GitHub::Grep.new.code_use(/["':]#{feature_name_in_code}/,
                                              /#{feature_name_in_code}_enabled\?/,
                                              /#{feature_name_in_code}_required/,
                                              dirs: %w[app config jobs lib packages :(exclude)packages/*/test/* :(exclude)config/schema*.graphql])
  end

  # Public: Returns Flipper::FeatureCheckContext that can be used to check for open gates
  def generate_context(actor)
    values = raw_feature.gate_values
    actor = gate(:actor).wrap(actor) unless actor.nil?
    Flipper::FeatureCheckContext.new(
      feature_name: raw_feature.name,
      values: values,
      thing: actor,
    )
  end

  # Public: Determines if a feature is always enabled for a given actor
  # regardless of the percentage-of-time setting.
  #
  # Returns true if the feature is always enabled for this actor (i.e., would
  # still be enabled even if percentage-of-time were set to 0), false
  # otherwise.
  def always_enabled?(actor)
    context = generate_context(actor)
    raw_feature.gates
      .reject { |gate| gate.key == :percentage_of_time } # reject the only non-deterministic gate
      .any? { |gate| gate.open?(context) }
  end

  # Public: Determines open gates for a given actor
  #
  # Returns an Array of Flipper::Gates
  # If a boolean gate is active which globally enables the feature only that gate will be returned
  def open_gates(actor)
    context = generate_context(actor)
    raw_feature.gates.select { |gate| gate.open?(context) }
  end

  # Public: Determines if a feature is enabled for everyone. This can return
  # true even when #on? returns false if the feature is enabled 100% of the
  # time or for 100% of actors.
  def fully_enabled?
    case state
    when :on
      true
    when :off
      false
    when :conditional
      percentage_of_actors_value == 100 || percentage_of_time_value == 100
    end
  end

  # Public: Determines if a feature is disabled for everyone. This can return
  # true even when #off? returns false if the feature is enabled 0% of the time
  # and not enabled for any groups or actors.
  def fully_disabled?
    case state
    when :on
      false
    when :off
      true
    when :conditional
      percentage_of_actors_value == 0 &&
        percentage_of_time_value == 0 &&
        groups_value.empty? &&
        actors_value.empty?
    end
  end

  def self.viewer_can_read?(viewer)
    return false unless GitHub.flipper_graphql_enabled?
    return false unless viewer
    return true if viewer.can_have_granular_permissions? &&
      Apps::Privileged.capable?(:read_flipper_features, app: viewer.integration)

    viewer.github_developer? || viewer.site_admin?
  end

  def self.async_viewer_can_read?(viewer)
    Promise.resolve(viewer_can_read?(viewer))
  end

  def async_viewer_can_read?(viewer)
    self.class.async_viewer_can_read?(viewer)
  end

  def async_viewer_can_delete?(viewer)
    self.class.async_viewer_can_read?(viewer)
  end

  def async_description_html_for(viewer)
    async_github_repo = Platform::Loaders::ActiveRecord.load(User, "github", column: :login, case_sensitive: false).then do |github_org|
      Platform::Loaders::RepositoryByName.load(github_org.id, "github") if github_org
    end

    async_github_repo.then do |github_repo|
      context = T.let({
        current_user: viewer,
        entity:       github_repo,
      }, T::Hash[T.untyped, T.untyped])

      GitHub::Goomba::MarkdownPipeline.async_to_html(description, context)
    end
  end

  def description_html_for(viewer)
    async_description_html_for(viewer).sync
  end

  def platform_type_name
    "Feature"
  end

  def number_of_actor_gates
    flipper_gates.actor_gates.size
  end

  # Groups actor IDs by the class through which the actor was granted access to the feature.
  #
  # Returns an Array of tuples, where each tuple is of the form [Class, [Integer]] e.g.
  # [[User, [123, 456]], [Organization, [789]]].
  def actor_ids_by_class
    actor_ids.group_by(&:first).map do |actor_class, actors|
      ids = actors.map(&:second)

      begin
        actor_class = actor_class.constantize
      rescue NameError
      end

      [actor_class, ids]
    end
  end

  # Returns the class names of all of the registered actors on the feature
  def actor_types
    self.class.connection.select_rows(Arel.sql(<<-SQL, id: id))
      SELECT DISTINCT SUBSTRING_INDEX(`value`, ":", 1) AS actor_type
      FROM flipper_gates
      WHERE `name` = "actors" AND `flipper_feature_id` = :id
      ORDER BY `actor_type` ASC
    SQL
  end

  def team_must_be_part_of_github_org
    return if Rails.env.development?

    if github_org_team_id.present? && !team_is_under_github_org?
      errors.add(:github_org_team_id, "team must be part of GitHub org")
    end
  end

  def team_is_under_github_org?
    github_org_team&.organization_id == GITHUB_ORG_ID
  end

  def big_feature?
    ::Flipper::Config.big_features.include?(name)
  end

  def show_big_feature_warning?
    !big_feature? && flipper_gates.actor_gates.size > BIG_FEATURE_WARNING_THRESHOLD
  end

  def most_recent_gate_updated_at
    flipper_gates.order(updated_at: :desc).first&.updated_at
  end

  ALLOWED_NON_GITHUB_ORGS = %w(
    microsoft
    integrations
  )
  def github_enabled?
    return false if fully_enabled?

    # Group for staff shipping
    return true if groups_value.include?(PREVIEW_FEATURES_GROUP_NAME)

    # If group not enabled, check the actors directly
    all_actors = actors
    return false if all_actors.empty?

    github_org_id = Rails.env.development? ? Organization.find_by_login("github").id : GITHUB_ORG_ID
    all_actors.all? do |actor|
      case actor
      when Organization
        actor.id == github_org_id
      when User
        actor.employee?
      when Team
        actor.organization_id == github_org_id
      when Repository
        next false if actor.organization_id.nil?
        next true if actor.organization_id == github_org_id
        # Allow some non-github repos to be enabled too
        ALLOWED_NON_GITHUB_ORGS.include?(T.unsafe(actor.organization).name.downcase)
      else
        false
      end
    end
  end

  def github_teams
    return @github_teams if defined?(@github_teams)
    github_org_id = Rails.env.development? ? Organization.find_by_login("github").id : GITHUB_ORG_ID
    @github_teams = actors.select { |a| a.is_a?(Team) && a.organization_id == github_org_id }
  end

  def github_employees
    return @github_employees if defined?(@github_employees)
    @github_employees = actors.select { |a| a.is_a?(User) && a.employee? }
  end

  def private_github_repos
    return @private_github_repos if defined?(@private_github_repos)
    github_org_id = Rails.env.development? ? Organization.find_by_login("github").id : GITHUB_ORG_ID
    @private_github_repos = actors.select { |a| a.is_a?(Repository) && a.organization_id == github_org_id && a.private? && a.writable? }
  end

  def public_github_repos
    return @public_github_repos if defined?(@public_github_repos)
    github_org_id = Rails.env.development? ? Organization.find_by_login("github").id : GITHUB_ORG_ID
    @public_github_repos = actors.select { |a| a.is_a?(Repository) && a.organization_id == github_org_id && !a.private? && a.writable? }
  end

  def non_github_repos
    return @non_github_repos if defined?(@non_github_repos)
    github_org_id = Rails.env.development? ? Organization.find_by_login("github").id : GITHUB_ORG_ID
    @non_github_repos = actors.select { |a| a.is_a?(Repository) && a.organization_id != github_org_id && a.writable? }
  end

  # Public: Often service names will have `github/` prepended. This adds little
  # value to the consumers of this information in the context of feature flags.
  # So this method removes the prepended text if it exists.
  #
  # Returns a String
  def short_service_name
    return service_name unless T.unsafe(service_name).starts_with?("github/")

    T.unsafe(service_name).sub("github/", "")
  end

  # Public: tracking issue urls can be pretty long. This method shortens them to
  # a format closer to what our markdown pipeline does.
  #
  # Example:
  #  "https://github.com/github/issues/issues/123" => "github/issues#123"
  #
  # Returns a String
  def short_tracking_issue_url
    T.unsafe(tracking_issue_url)
      .downcase
      .sub("https://github.com/", "")
      .sub(/\/(?:issues|pull|discussions)\/(\d+)/, "#\\1")
  end

  # Public: is a feature flag past its exptected removal date and not long
  # lived?
  #
  # Returns a Boolean.
  def stale?
    !long_lived && stale_at.present? && T.unsafe(stale_at) < DateTime.current
  end

  # Public: returns all the gates that are not stamp specific
  #
  # Retuns an Array of FlipperGate
  def shared_gates
    flipper_gates.where(name:  %w(boolean percentage_of_actors percentage_of_time groups))
  end

  private

  # Internal: Fetches all serialized resources that have been given access to the
  # feature.
  #
  # Returns Array of [String, Integer] elements
  def actor_ids
    raw_feature.actors_value.collect { |actor| GitHub::FlipperActor.flipper_id_to_parts(actor) }
  end

  # Internal: The Flipper::Feature
  def raw_feature
    @raw_feature ||= GitHub.flipper[name.to_sym]
  end

  # Internal: instrument creation of a feature
  def instrument_create
    instrument :create, operation: :create
  end

  # Internal: instrument update of a feature's long_lived field
  def instrument_update
    return unless previous_changes.has_key?(:long_lived)

    changes = {
      long_lived_was: previous_changes[:long_lived].first,
      long_lived: previous_changes[:long_lived].last
    }

    instrument :update, operation: :update, changes: changes
  end

  # Internal: Instrument deletion of a feature
  def instrument_deletion
    instrument :destroy, operation: :destroy
  end

  # Internal: Ensures Flipper cache is cleared
  def cleanup_raw_feature
    GitHub.flipper.adapter.remove(raw_feature)
  end

  # Internal: event payload for Instrumentation
  def event_payload
    {
      feature_name: name,
    }
  end

  def event_prefix
    :feature
  end

  # Internal: validator for name byte size
  def name_byte_size
    # name is validated for presence, so we can safely return early here
    return if name.nil?
    if name.bytesize > 200
      errors.add(:name, "is too long (maximum is 200 bytes)")
    end
  end
end

# rubocop:enable GitHub/FeatureManagement/NoFlipperFeatureUsage
