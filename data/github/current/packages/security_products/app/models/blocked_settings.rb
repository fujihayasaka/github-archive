# typed: strict
# frozen_string_literal: true

# At the business or owner level, users can initiate a background process that attempts to change a setting on multiple repositories.
# In order to avoid a user changing a setting while this background process is ongoing, all related settings should be blocked.
#
# Settings are dependent on other settings. For example, while advanced security is being enabled, secret scanning cannot be changed (and vice versa).
#
# The BlockedSettings class provides an easy-to-use way to know which settings should be currently blocked.
#
# Examples:
#
#   Given an organization, to know if secret scanning settings should be blocked for all of its repositories:
#     BlockedSettings.new(org).secret_scanning?
#
#   Given a business, to know if secret scanning settings should be blocked for all repositories in all of its organizations:
#     BlockedSettings.new(biz).secret_scanning?
class BlockedSettings
  extend T::Generic

  include Enumerable
  include GitHub::Memoizer

  Elem = type_member { { fixed: Symbol } }

  BLOCKING_SETTINGS = T.let({
    # automatically_enable_for_new_repos represent a setting that is automatically enabled or disabled for new repos.
    automatically_enable_for_new_repos: [
      :advanced_security_disable_all,
      :advanced_security_enable_all,
      :advanced_security_user_namespace_enable_all,
      :advanced_security_user_namespace_disable_all,
      :auto_codeql_disable_all,
      :auto_codeql_enable_all,
      :auto_codeql_enable_all_extended,
      :innersource_advisories_enable_all,
      :innersource_advisories_disable_all,
      :secret_scanning_disable_all,
      :secret_scanning_enable_all,
      :secret_scanning_validity_checks_disable_all,
      :secret_scanning_validity_checks_enable_all,
      :secret_scanning_push_protection_disable_all,
      :secret_scanning_push_protection_enable_all,
      :secret_scanning_lower_confidence_patterns_enable_all,
      :secret_scanning_lower_confidence_patterns_disable_all,
      :secret_scanning_generic_secrets_enable_all,
      :secret_scanning_generic_secrets_disable_all
    ],

    advanced_security_enable_all: [
      :advanced_security_disable_all,
      :advanced_security_enable_all,
      :advanced_security_user_namespace_enable_all,
      :advanced_security_user_namespace_disable_all,
      :auto_codeql_disable_all,
      :auto_codeql_enable_all,
      :auto_codeql_enable_all_extended,
      :innersource_advisories_enable_all,
      :innersource_advisories_disable_all,
      :secret_scanning_disable_all,
      :secret_scanning_enable_all,
      :secret_scanning_validity_checks_disable_all,
      :secret_scanning_validity_checks_enable_all,
      :secret_scanning_push_protection_disable_all,
      :secret_scanning_push_protection_enable_all,
      :secret_scanning_lower_confidence_patterns_enable_all,
      :secret_scanning_lower_confidence_patterns_disable_all,
      :secret_scanning_generic_secrets_enable_all,
      :secret_scanning_generic_secrets_disable_all
    ],
    advanced_security_disable_all: [
      :advanced_security_disable_all,
      :advanced_security_enable_all,
      :advanced_security_user_namespace_enable_all,
      :advanced_security_user_namespace_disable_all,
      :auto_codeql_disable_all,
      :auto_codeql_enable_all,
      :auto_codeql_enable_all_extended,
      :innersource_advisories_enable_all,
      :innersource_advisories_disable_all,
      :secret_scanning_disable_all,
      :secret_scanning_enable_all,
      :secret_scanning_validity_checks_disable_all,
      :secret_scanning_validity_checks_enable_all,
      :secret_scanning_push_protection_disable_all,
      :secret_scanning_push_protection_enable_all,
      :secret_scanning_lower_confidence_patterns_enable_all,
      :secret_scanning_lower_confidence_patterns_disable_all,
      :secret_scanning_generic_secrets_enable_all,
      :secret_scanning_generic_secrets_disable_all
    ],
    advanced_security_user_namespace_enable_all: [
      :advanced_security_disable_all,
      :advanced_security_enable_all,
      :advanced_security_user_namespace_enable_all,
      :advanced_security_user_namespace_disable_all,
      :secret_scanning_disable_all,
      :secret_scanning_enable_all,
      :secret_scanning_validity_checks_disable_all,
      :secret_scanning_validity_checks_enable_all,
      :secret_scanning_push_protection_disable_all,
      :secret_scanning_push_protection_enable_all
    ],
    advanced_security_user_namespace_disable_all: [
      :advanced_security_disable_all,
      :advanced_security_enable_all,
      :advanced_security_user_namespace_enable_all,
      :advanced_security_user_namespace_disable_all,
      :secret_scanning_disable_all,
      :secret_scanning_enable_all,
      :secret_scanning_validity_checks_disable_all,
      :secret_scanning_validity_checks_enable_all,
      :secret_scanning_push_protection_disable_all,
      :secret_scanning_push_protection_enable_all
    ],
    auto_codeql_enable_all: [
      :advanced_security_disable_all,
      :advanced_security_enable_all,
      :advanced_security_user_namespace_enable_all,
      :advanced_security_user_namespace_disable_all,
      :auto_codeql_disable_all,
      :auto_codeql_enable_all,
      :auto_codeql_enable_all_extended
    ],
    auto_codeql_enable_all_extended: [
      :advanced_security_disable_all,
      :advanced_security_enable_all,
      :advanced_security_user_namespace_enable_all,
      :advanced_security_user_namespace_disable_all,
      :auto_codeql_disable_all,
      :auto_codeql_enable_all,
      :auto_codeql_enable_all_extended
    ],
    auto_codeql_disable_all: [
      :advanced_security_disable_all,
      :advanced_security_enable_all,
      :advanced_security_user_namespace_enable_all,
      :advanced_security_user_namespace_disable_all,
      :auto_codeql_disable_all,
      :auto_codeql_enable_all,
      :auto_codeql_enable_all_extended
    ],
    innersource_advisories_enable_all: [
      :advanced_security_disable_all,
      :advanced_security_enable_all,
      :innersource_advisories_enable_all,
      :innersource_advisories_disable_all
    ],
    innersource_advisories_disable_all: [
      :advanced_security_disable_all,
      :advanced_security_enable_all,
      :innersource_advisories_enable_all,
      :innersource_advisories_disable_all
    ],
    secret_scanning_enable_all: [
      :advanced_security_disable_all,
      :advanced_security_enable_all,
      :advanced_security_user_namespace_enable_all,
      :advanced_security_user_namespace_disable_all,
      :secret_scanning_disable_all,
      :secret_scanning_enable_all,
      :secret_scanning_validity_checks_disable_all,
      :secret_scanning_validity_checks_enable_all,
      :secret_scanning_push_protection_disable_all,
      :secret_scanning_push_protection_enable_all,
      :secret_scanning_lower_confidence_patterns_enable_all,
      :secret_scanning_lower_confidence_patterns_disable_all,
      :secret_scanning_generic_secrets_enable_all,
      :secret_scanning_generic_secrets_disable_all
    ],
    secret_scanning_disable_all: [
      :advanced_security_disable_all,
      :advanced_security_enable_all,
      :advanced_security_user_namespace_enable_all,
      :advanced_security_user_namespace_disable_all,
      :secret_scanning_disable_all,
      :secret_scanning_enable_all,
      :secret_scanning_validity_checks_disable_all,
      :secret_scanning_validity_checks_enable_all,
      :secret_scanning_push_protection_disable_all,
      :secret_scanning_push_protection_enable_all,
      :secret_scanning_lower_confidence_patterns_enable_all,
      :secret_scanning_lower_confidence_patterns_disable_all,
      :secret_scanning_generic_secrets_enable_all,
      :secret_scanning_generic_secrets_disable_all
    ],
    secret_scanning_push_protection_enable_all: [
      :advanced_security_disable_all,
      :advanced_security_enable_all,
      :advanced_security_user_namespace_enable_all,
      :advanced_security_user_namespace_disable_all,
      :secret_scanning_disable_all,
      :secret_scanning_enable_all,
      :secret_scanning_push_protection_disable_all,
      :secret_scanning_push_protection_enable_all
    ],
    secret_scanning_push_protection_disable_all: [
      :advanced_security_disable_all,
      :advanced_security_enable_all,
      :advanced_security_user_namespace_enable_all,
      :advanced_security_user_namespace_disable_all,
      :secret_scanning_disable_all,
      :secret_scanning_enable_all,
      :secret_scanning_push_protection_disable_all,
      :secret_scanning_push_protection_enable_all
    ],
    secret_scanning_validity_checks_enable_all: [
      :advanced_security_disable_all,
      :advanced_security_enable_all,
      :advanced_security_user_namespace_enable_all,
      :advanced_security_user_namespace_disable_all,
      :secret_scanning_disable_all,
      :secret_scanning_enable_all,
      :secret_scanning_validity_checks_disable_all,
      :secret_scanning_validity_checks_enable_all
    ],
    secret_scanning_validity_checks_disable_all: [
      :advanced_security_disable_all,
      :advanced_security_enable_all,
      :advanced_security_user_namespace_enable_all,
      :advanced_security_user_namespace_disable_all,
      :secret_scanning_disable_all,
      :secret_scanning_enable_all,
      :secret_scanning_validity_checks_disable_all,
      :secret_scanning_validity_checks_enable_all
    ],
    secret_scanning_lower_confidence_patterns_enable_all: [
      :advanced_security_disable_all,
      :advanced_security_enable_all,
      :secret_scanning_disable_all,
      :secret_scanning_enable_all,
      :secret_scanning_lower_confidence_patterns_disable_all,
      :secret_scanning_lower_confidence_patterns_enable_all
    ],
    secret_scanning_lower_confidence_patterns_disable_all: [
      :advanced_security_disable_all,
      :advanced_security_enable_all,
      :secret_scanning_disable_all,
      :secret_scanning_enable_all,
      :secret_scanning_lower_confidence_patterns_disable_all,
      :secret_scanning_lower_confidence_patterns_enable_all
    ],
    secret_scanning_generic_secrets_enable_all: [
      :advanced_security_disable_all,
      :advanced_security_enable_all,
      :secret_scanning_disable_all,
      :secret_scanning_enable_all,
      :secret_scanning_generic_secrets_disable_all,
      :secret_scanning_generic_secrets_enable_all
    ],
    secret_scanning_generic_secrets_disable_all: [
      :advanced_security_disable_all,
      :advanced_security_enable_all,
      :secret_scanning_disable_all,
      :secret_scanning_enable_all,
      :secret_scanning_generic_secrets_disable_all,
      :secret_scanning_generic_secrets_enable_all
    ]
  }, T::Hash[Symbol, T::Array[Symbol]])

  MESSAGE_PREFACE_BIZ = "A change has been made to a configuration at either the enterprise or organization level."
  MESSAGE_PREFACES = T.let({
    advanced_security_enable_all: "GitHub Advanced Security is being enabled",
    advanced_security_disable_all: "GitHub Advanced Security is being disabled",
    advanced_security_user_namespace_enable_all: "GitHub Advanced Security for user namespace repositories is being enabled",
    advanced_security_user_namespace_disable_all: "GitHub Advanced Security for user namespace repositories is being disabled",
    auto_codeql_enable_all: "code scanning is being enabled",
    auto_codeql_enable_all_extended: "code scanning is being enabled",
    auto_codeql_disable_all: "code scanning is being disabled",
    innersource_advisories_enable_all: "innersource advisories are being enabled",
    innersource_advisories_disable_all: "innersource advisories are being disabled",
    secret_scanning_enable_all: "secret scanning is being enabled",
    secret_scanning_disable_all: "secret scanning is being disabled",
    secret_scanning_validity_checks_enable_all: "validity checks are being enabled",
    secret_scanning_validity_checks_disable_all: "validity checks are being disabled",
    secret_scanning_push_protection_enable_all: "push protection is being enabled",
    secret_scanning_push_protection_disable_all: "push protection is being disabled"
  }, T::Hash[Symbol, String])

  sig { returns(RepoCounter) }
  attr_reader :repo_counter

  sig { params(owner: T.any(Business, Organization, User)).void }
  def initialize(owner)
    @owner = owner
    @repo_counter = T.let(RepoCounter.new(@owner), RepoCounter)
  end

  # BlockedSettings is Enumerable and must override `each`.
  sig { override.params(blk: T.proc.params(arg0: Symbol).returns(BasicObject)).returns(T.self_type) }
  def each(&blk)
    entries.each(&blk)
    self
  end

  # The array of settings that are blocked.
  #
  # NOTE: `entries` is an alias of `to_a`.
  sig { override.returns(T::Array[Symbol]) }
  memoize def entries
    blocked = Set.new

    blockers.each do |ut_selected|
      T.must(BLOCKING_SETTINGS[ut_selected]).each do |setting|
        blocked << setting
      end
    end

    blocked.to_a
  end

  # The array of settings that are causing settings to be blocked.
  sig { returns(T::Array[Symbol]) }
  memoize def blockers
    return [:automatically_enable_for_new_repos] if automatically_enable_for_new_repos_in_progress?

    set = Set.new

    # All-or-nothing blocking for enable-all job
    # For query performance on large enterprises/organizations, we search active job statuses by prefix.
    kv_prefix =
      if @owner.is_a?(Business)
        SecurityAnalysisSettingsUpdateJob.job_id_business_prefix(@owner)
      else
        SecurityAnalysisSettingsUpdateJob.job_id_owner_prefix(@owner)
      end

    SecurityProductsEnablement::JobStatus.find_prefix(kv_prefix).each do |job_status|
      next if !job_status&.pending? && !job_status&.started?
      update_type = job_status.id.split(".").last.to_sym
      # allowlist; not all settings cause blocking (e.g. dependency features)
      next unless BLOCKING_SETTINGS.keys.include?(update_type)
      set << update_type
    end

    # Fanout blocking by pending repo count
    BLOCKING_SETTINGS.keys.each do |setting|
      set << setting if repo_counter.blocked?(setting)
    end

    set.to_a
  end

  sig { returns(String) }
  memoize def inspect
    entries.inspect
  end
  alias to_s inspect

  sig { returns(String) }
  memoize def message
    return "" unless any?
    [preface, message_end].reject(&:empty?).join(" ")
  end

  sig { returns(String) }
  memoize def preface
    return MESSAGE_PREFACE_BIZ if @owner.instance_of?(Business)

    prefaces = blockers
      .each_with_object([]) { |setting, acc| acc << MESSAGE_PREFACES[setting] }
      .compact

    return "" if prefaces.empty?

    prefaces
      .to_sentence
      .upcase_first + "."
  end

  sig { returns(String) }
  def repo_message
    level = @owner.instance_of?(User) ? "user" : "organization"

    "A change has been made to this configuration at the #{level} level. #{message_end}"
  end

  # Are GHAS settings blocked?
  sig { returns(T::Boolean) }
  memoize def advanced_security?
    include?(:advanced_security_enable_all) ||
      include?(:advanced_security_disable_all)
  end

  sig { returns(T::Boolean) }
  memoize def advanced_security_user_namespace?
    include?(:advanced_security_user_namespace_enable_all) ||
      include?(:advanced_security_user_namespace_disable_all)
  end

  # Are code scanning settings blocked?
  sig { returns(T::Boolean) }
  memoize def code_scanning?
    include?(:auto_codeql_enable_all) ||
      include?(:auto_codeql_enable_all_extended) ||
      include?(:auto_codeql_disable_all)
  end

  # Are secret scanning settings blocked?
  sig { returns(T::Boolean) }
  memoize def secret_scanning?
    include?(:secret_scanning_enable_all) ||
      include?(:secret_scanning_disable_all)
  end

  # Are secret scanning validity check settings blocked?
  sig { returns(T::Boolean) }
  memoize def validity_checks?
    include?(:secret_scanning_validity_checks_enable_all) ||
      include?(:secret_scanning_validity_checks_disable_all)
  end

  # Are secret scanning push protection settings blocked?
  sig { returns(T::Boolean) }
  memoize def push_protection?
    include?(:secret_scanning_push_protection_enable_all) ||
      include?(:secret_scanning_push_protection_disable_all)
  end

  # Are secret scanning scan for non-provider patterns settings blocked?
  sig { returns(T::Boolean) }
  memoize def lower_confidence_patterns?
    include?(:secret_scanning_lower_confidence_patterns_enable_all) ||
      include?(:secret_scanning_lower_confidence_patterns_disable_all)
  end

  # Are secret scanning generic secrets settings blocked?
  sig { returns(T::Boolean) }
  memoize def generic_secrets?
    include?(:secret_scanning_generic_secrets_enable_all) ||
      include?(:secret_scanning_generic_secrets_disable_all)
  end

  sig { returns(T::Boolean) }
  memoize def innersource_advisories?
    include?(:innersource_advisories_enable_all) ||
      include?(:innersource_advisories_disable_all)
  end

  private

  sig { returns(T::Boolean) }
  memoize def automatically_enable_for_new_repos_in_progress?
    biz = @owner if @owner.instance_of?(Business)
    biz = @owner.business if @owner.instance_of?(Organization)

    return false if biz.nil?

    job_status = UpdateBusinessSecurityFeatureForNewReposJob.status(biz)
    !!job_status&.pending? || !!job_status&.started?
  end

  sig { returns(String) }
  memoize def message_end
    preamble = "Some features under GitHub Advanced Security cannot be enabled or disabled until changes are propagated to all"

    if @owner.instance_of?(Business)
      return "#{preamble} organizations in this enterprise."
    end

    if @owner.instance_of?(Organization)
      return "#{preamble} repositories in this organization."
    end

    "#{preamble} repositories owned by this user."
  end

  # The KV store is used to track which settings are blocked due to an ongoing background process.
  # RepoCounter is a helper class to interact with the KV store.
  class RepoCounter
    sig { returns(T.any(Business, Organization, User)) }
    attr_reader :owner

    sig { params(owner: T.any(Business, Organization, User)).void }
    def initialize(owner)
      @owner = owner
    end

    sig { params(setting: Symbol).returns(Integer) }
    def increment(setting)
      key = kv_key(setting)
      result = ActiveRecord::Base.connected_to(role: :writing) do
        SecurityProductsEnablement::KV.store.increment(key, expires: 10.minutes.from_now)
      end

      clear_memoized_counts
      result
    end

    sig { params(setting: Symbol).returns(Integer) }
    def decrement(setting)
      key = kv_key(setting)
      result = ActiveRecord::Base.connected_to(role: :writing) do
        SecurityProductsEnablement::KV.store.increment(key, amount: -1, expires: 10.minutes.from_now)
      end

      clear_memoized_counts
      result
    end

    sig { params(setting: Symbol).returns(T::Boolean) }
    def blocked?(setting)
      value(setting) > 0
    end

    sig { params(setting: Symbol).returns(Integer) }
    def value(setting)
      if owner.instance_of?(Business)
        return owner.organization_ids
          .map do |org_id|
            key = "#{kv_key_business_prefix}:#{org_id}:#{setting}"
            (all_business[key] || 0).to_i
          end
          .first { |c| c > 0 } || 0
      end

      (all_organization[kv_key(setting)] || 0).to_i
    end

    private

    sig { returns(T::Hash[String, Integer]) }
    def all_business
      @_all_business ||= T.let(SecurityProductsEnablement::KV.store.mget_prefix(kv_key_business_prefix).value { {} }, T.untyped)
    end

    sig { returns(T::Hash[String, Integer]) }
    def all_organization
      @_all_organization ||= T.let(SecurityProductsEnablement::KV.store.mget_prefix(kv_key_organization_prefix).value { {} }, T.untyped)
    end

    sig { void }
    def clear_memoized_counts
      @_all_business = nil
      @_all_organization = nil
    end

    sig { returns(String) }
    def kv_key_business_prefix
      "security_products:enablement_count:#{owner_business_id}"
    end

    sig { returns(String) }
    def kv_key_organization_prefix
      raise NotImplementedError if owner.instance_of?(Business)
      "#{kv_key_business_prefix}:#{owner.id}"
    end

    sig { params(setting: Symbol).returns(String) }
    def kv_key(setting)
      "#{kv_key_organization_prefix}:#{setting}"
    end

    sig { returns(Integer) }
    def owner_business_id
      business =
        if owner.instance_of?(Business)
          owner
        elsif owner.instance_of?(Organization)
          T.cast(owner, Organization).business
        end

      business&.id || 0
    end
  end
end
