# typed: true
# frozen_string_literal: true

class VulnerableVersionRange < ApplicationRecord::Notify
  extend T::Helpers
  include GitHub::Relay::GlobalIdentification
  include DependabotAlerts::UpstreamModel
  include AdvisoryDB::ScopedVulnerabilityHelper
  include GitHub::VexiActor

  sig { returns(T.nilable(T::Boolean)) }
  attr_accessor :skip_affects_validation

  sig { returns(T.nilable(T::Boolean)) }
  attr_accessor :skip_requirements_validation

  @skip_affects_validation = T.let(nil, T.nilable(T::Boolean))
  @skip_requirements_validation = T.let(nil, T.nilable(T::Boolean))

  belongs_to :vulnerability, touch: true

  has_many :vulnerable_version_range_alerting_processes

  has_many :repository_vulnerability_alerts, inverse_of: :vulnerable_version_range
  after_destroy_commit do |vvr|
    WithdrawRepositoryVulnerabilityAlertsJob.perform_later(vulnerable_version_range_id: vvr.id)
  end

  PUBLIC_ECOSYSTEMS = T.let(::AdvisoryDB::Ecosystems.api_filter, T::Array[String])

  validates :vulnerability, presence: true

  # Include Dependabot Alerts search index synchronization
  include Search::DependabotAlerts::VulnerableVersionRange
  after_update_commit :synchronize_dependabot_alerts_search_index, if: :synchronize_dependabot_search_index?


  validates :ecosystem, inclusion: ::AdvisoryDB::Ecosystems.database_enum, presence: true
  validates :affects, presence: true, unless: :skip_affects_validation

  AFFECTS_FORMAT = /\A\S+\z/
  validates :affects, format: { with: AFFECTS_FORMAT, message: "can not contain whitespace" }, unless: :skip_affects_validation

  # Validate requirement strings format
  # The requirement string delineates a _version range_, from a minimum value to a maximum.
  # Requirements strings must look like one of the following:
  # - `= 1.2.3`
  # - `< 1.2`
  # - `<= 234.beta6`
  # - `>= 1.0, < 1.5`
  # white spacing is strictly enforced
  REQUIREMENTS_FORMAT = %r{
    \A
    # Two basic versions, those with the comma, and those without
    (
      (?: # version without comma
        (?<only_operator>=|<|<=|>|>=)
        (?:[ ])
        (?<only_version>\d[^\s,]*)
      )
      |
      (?: # version with comma
        (?<lower_operator>>|>=) # restrict to it starting with greater-than or greater-than-or-equal-to
        (?:[ ])
        (?<lower_version>\d[^\s,]*)
        ,
        (?:[ ])
        (?<upper_operator><|<=) # likewise upper operator must be less-than
        (?:[ ])
        (?<upper_version>\d[^\s,]*)
      )
    )
    \z
  }x
  validates :requirements, presence: true, format: {
    with: REQUIREMENTS_FORMAT,
    message: "not a valid requirements string",
  }, unless: :skip_requirements_validation

  scope :has_public_ecosystem, -> {
    where(ecosystem: PUBLIC_ECOSYSTEMS)
  }

  scope :disclosed, -> {
    has_public_ecosystem.
      joins(:vulnerability).
      merge(Vulnerability.open_source.not_simulation)
  }

  # TODO: Remove?
  #
  # This does not appear to be used anywhere at time of writing.
  scope :disclosed_and_reviewed, -> {
    has_public_ecosystem.
    joins(:vulnerability).
    merge(Vulnerability.open_source.not_simulation.has_been_reviewed)
  }

  # this filters unpublished Vulnerabilities from
  # the current set of vuln versions we want to alert on
  #
  # this also filters malware vulnerabilities from the current set of
  # vuln versions if the :dependabot_allow_malware feature is not enabled
  # because we have noticed that a lot of the alerts are false positives.
  # Check out https://github.com/github/team-advisory-database/issues/2902 for more details.
  #
  # this also filters innersource vulnerabilities from the current set of
  # vuln versions if the :innersource_alerting feature is not enabled
  # because innersource alerting is not supported yet by other services.
  # Check out https://github.com/github/dependabot-updates/issues/12499 for more details.
  #
  scope :dependabot_alertable, -> {
    relation = joins(:vulnerability).merge(Vulnerability.published)

    unless FeatureFlag.vexi.enabled?(:dependabot_allow_malware, default: false)
      relation = relation.merge(Vulnerability.general_classification)
    end

    unless FeatureFlag.vexi.enabled?(:innersource_alerting, default: false)
      relation = relation.merge(Vulnerability.open_source)
    end

    relation
  }

  # These _FOR_ENTERPRISE constants allow us to enforce that all aspects of an advisory (vuln attributes + associations)
  # missing from enterprise environments have been intentionally excluded (eg. because it's environmentally-dependent
  # like a user id) rather than overlooked.
  ATTRIBUTES_FOR_ENTERPRISE = T.let(%w(
    affected_functions
    affected_functions_json
    affects
    dotcom_id
    ecosystem
    fixed_in
    id
    requirements
  ).freeze, T::Array[String])

  ATTRIBUTES_NOT_FOR_ENTERPRISE = T.let([
    "vulnerability_id", # the model is built through the association so this gets set automatically
    "created_at", # this timestamp isn't displayed or useful to the product
    "updated_at", # this timestamp isn't displayed or useful to the product
  ].freeze, T::Array[String])

  sig { returns(T::Array[String]) }
  def self.attributes_for_enterprise
    ATTRIBUTES_FOR_ENTERPRISE
  end

  sig { returns(T::Boolean) }
  def has_public_ecosystem?
    PUBLIC_ECOSYSTEMS.include?(ecosystem)
  end

  sig { returns(T::Hash[String, T.untyped]) }
  def simple_attributes
    attributes.except("id", "vulnerability_id", "created_at", "updated_at")
  end

  # Requirements strings that indicate a package-level malware advisory
  # (i.e. all versions are affected, not just specific ones).
  # Must cover all zero-version variants that `malware_subtype` considers :Package.
  PACKAGE_LEVEL_REQUIREMENTS = T.let([">= 0", "> 0", ">= 0.0", "> 0.0", ">= 0.0.0", "> 0.0.0"].freeze, T::Array[String])

  # Returns the malware subtype based on the affected version range.
  sig { returns(Symbol) }
  def malware_subtype
    match = requirements&.match(REQUIREMENTS_FORMAT)
    return :Package unless match

    # If the requirement is a single >= or > with a base version of 0 (e.g., ">= 0", "> 0"),
    if match[:only_operator].present? && %w[>= >].include?(match[:only_operator])
      version = match[:only_version].to_s
      return :Package if version.gsub(".", "").match?(/\A0+\z/) # checks if the version is 0 ("0", "0.0", "0.0.0")
    end

    :Version
  end

  sig { params(versions: T::Array[String], operator: Symbol).returns(T::Boolean) }
  def affects_versions?(*versions, operator: :and)
    return false if versions.empty?

    if operator == :or
      versions.flatten.any? do |version_string|
        satisfied_by?(version_string)
      end
    else
      versions.flatten.all? do |version_string|
        satisfied_by?(version_string)
      end
    end
  end

  # This works because all requirement strings follow a stable format provided by the regex above and
  # all the dependabot version classes inherit Gem::Version
  sig { params(version_string: String).returns(T::Boolean) }
  def satisfied_by?(version_string)
    version = dependabot_version_class.new(version_string)

    # Split up each requirement's operator and version in order to translate ecosystem specific range boundaries
    # into Gem::Version format and join it back together. This helps us with some edge cases around prereleases being
    # compared properaly.
    reqs = requirements.split(",").map do |req|
      x = T.must(req.strip.match(REQUIREMENTS_FORMAT))
      requirement_version = dependabot_version_class.new(x[:only_version])
      [x[:only_operator], requirement_version.version].join(" ")
    end

    Gem::Requirement.new(reqs).satisfied_by?(version)

  rescue ArgumentError => e
    if e.message.include?("Malformed version")
      return false
    end

    Failbot.report(e)
  end

  def dependabot_version_class
    Dependabot.version_class_for(ecosystem)
  end

  sig { returns(T::Boolean) }
  def instrument_vulnerability_update?
    return false unless vulnerability&.disclosed?
    return true if destroyed?

    ecosystem_previously_changed? ||
      affects_previously_changed? ||
      fixed_in_previously_changed? ||
      requirements_previously_changed?
  end

  sig { returns(T::Boolean) }
  def previous_changes_affect_alerts?
    # these are the keys that impact alert generation
    # https://github.com/github/dependency-graph-api/blob/72379ad279f363d1adf3d6ee52ce2ec932cdb5ba/app/models/vulnerable_version_range.rb#L50-L58
    affects_previously_changed? || ecosystem_previously_changed? || requirements_previously_changed?
  end

  sig { returns(T::Boolean) }
  def alertable?
    has_public_ecosystem? && ::AdvisoryDB::Ecosystems.dependency_graph_supported_names.include?(ecosystem)
  end
end
