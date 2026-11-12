# typed: true
# frozen_string_literal: true

# Redis-backed record of a blocked dependency version, keyed by language
# (not package_manager) so a single block covers all toolchains for that
# language (e.g. `javascript` covers both `npm_and_yarn` and `bun`).
#
# Key pattern: `dep_block:<language>:<package_name>:<version>`
class BlockedDependency < T::Struct
  extend T::Sig

  Language = T.type_alias { String }

  KEY_PREFIX = "dep_block"
  DEFAULT_TTL = 1.week
  SCAN_BATCH_SIZE = 100

  class InvalidLanguageError < ArgumentError; end
  class InvalidVersionRequirementError < ArgumentError; end

  const :language, Language
  const :package_name, String
  const :version, String
  const :reason, T.nilable(String)
  const :blocked_by, T.nilable(String)
  const :blocked_at, String

  sig { params(_args: T.untyped).returns(String) }
  def to_json(*_args)
    {
      language: language,
      package_name: package_name,
      version: version,
      reason: reason,
      blocked_by: blocked_by,
      blocked_at: blocked_at,
    }.to_json
  end

  sig { params(json: String).returns(BlockedDependency) }
  def self.from_json(json)
    data = JSON.parse(json)
    new(
      language: data.fetch("language"),
      package_name: data.fetch("package_name"),
      version: data.fetch("version"),
      reason: data["reason"],
      blocked_by: data["blocked_by"],
      blocked_at: data.fetch("blocked_at"),
    )
  end

  sig { params(language: Language).void }
  def self.validate_language!(language)
    return if Languages::ALL.include?(language)

    raise InvalidLanguageError,
          "unknown language #{language.inspect}; " \
          "must be one of: #{Languages::ALL.join(', ')}"
  end

  # Accepts the same syntax as `ignore.versions` in dependabot.yml, plus the
  # `ALL_VERSIONS` sentinel.
  sig { params(language: Language, version: String).void }
  def self.validate_version!(language, version)
    return if version == Dependabot::Config::IgnoreCondition::ALL_VERSIONS

    package_manager = T.must(Ecosystems.package_managers_for_language(language).first)
    requirement_class = Dependabot::Utils.requirement_class_for_package_manager(package_manager)
    requirement_class.requirements_array(version)
  rescue StandardError => e
    # `requirements_array` raises `BadRequirementError` which is namespaced
    # per-ecosystem, so rescue broadly.
    raise InvalidVersionRequirementError,
          "#{version.inspect} is not a valid #{language} version requirement: #{e.message}"
  end

  sig do
    params(
      language: Language,
      package_name: String,
      version: String,
      reason: T.nilable(String),
      blocked_by: T.nilable(String),
      ttl: T.any(Integer, ActiveSupport::Duration),
    ).returns(BlockedDependency)
  end
  def self.create!(language:, package_name:, version:, reason: nil, blocked_by: nil, ttl: DEFAULT_TTL)
    validate_language!(language)
    validate_version!(language, version)

    record = new(
      language: language,
      package_name: package_name,
      version: version,
      reason: reason,
      blocked_by: blocked_by,
      blocked_at: Time.now.utc.iso8601,
    )

    redis.set(key_for(language, package_name, version), record.to_json, ex: ttl.to_i)
    record
  end

  sig { params(language: Language, package_name: String, version: String).returns(T::Boolean) }
  def self.exists?(language:, package_name:, version:)
    redis.exists?(key_for(language, package_name, version))
  end

  sig do
    params(language: Language, package_name: String, version: String).returns(T.nilable(BlockedDependency))
  end
  def self.find(language:, package_name:, version:)
    raw = redis.get(key_for(language, package_name, version))
    return nil unless raw

    from_json(raw)
  end

  sig { params(language: Language, package_name: String, version: String).returns(T::Boolean) }
  def self.destroy!(language:, package_name:, version:)
    redis.del(key_for(language, package_name, version)).positive?
  end

  sig { params(language: Language, package_name: String, version: String).returns(T.nilable(Integer)) }
  def self.ttl(language:, package_name:, version:)
    ttl = redis.ttl(key_for(language, package_name, version))
    # redis returns -2 if the key does not exist, -1 if it exists with no TTL.
    return nil if ttl.negative?

    ttl
  end

  sig { params(language: Language, package_name: String).returns(T::Array[BlockedDependency]) }
  def self.where(language:, package_name:)
    pattern = "#{key_prefix_for(language, package_name)}:*"
    fetch_records(pattern)
  end

  sig { returns(T::Array[BlockedDependency]) }
  def self.all
    fetch_records("#{KEY_PREFIX}:*")
  end

  sig { params(language: Language, package_name: String, version: String).returns(String) }
  def self.key_for(language, package_name, version)
    "#{key_prefix_for(language, package_name)}:#{version}"
  end

  sig { returns(::Redis) }
  def self.redis
    @redis ||= Dependabot.redis
  end

  class << self
    extend T::Sig

    sig { params(redis: ::Redis).returns(::Redis) }
    attr_writer :redis
  end

  sig { params(language: Language, package_name: String).returns(String) }
  private_class_method def self.key_prefix_for(language, package_name)
    "#{KEY_PREFIX}:#{language}:#{package_name}"
  end

  sig { params(pattern: String).returns(T::Array[BlockedDependency]) }
  private_class_method def self.fetch_records(pattern)
    keys = T.let([], T::Array[String])
    cursor = T.let("0", String)
    loop do
      cursor, batch = redis.scan(cursor, match: pattern, count: SCAN_BATCH_SIZE)
      keys.concat(batch)
      break if cursor == "0"
    end

    return [] if keys.empty?

    T.unsafe(redis).mget(*keys).compact.map { |raw| from_json(raw) }
  end
end
