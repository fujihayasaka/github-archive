# typed: strict
# frozen_string_literal: true

# A simple mixin for AR models that should be rate limited.
#
# class Foo < ActiveRecord::Base
#   belongs_to :user
#   include GitHub::RateLimitedCreation
# end
module GitHub::RateLimitedCreation
  extend T::Helpers
  requires_ancestor { ApplicationRecord::Base }

  ERROR_MESSAGE = "was submitted too quickly"

  LIMITS = T.let({
    user_minute:          80,
    user_hour:            500,
    installation_minute:  80,
    installation_hour:    500,

    # Repo creation gets its own limits to avoid diluting other
    # data creation limits while still allowing acceptable use.
    user_repo_minute:         50,
    user_repo_hour:           150,
    installation_repo_minute: 50,
    installation_repo_hour:   150
  }.freeze, T::Hash[Symbol, Integer])

  AUDIT_LOG_EVENT_KEY = :creation_rate_limit_exceeded

  sig { returns(T::Hash[Symbol, Integer]) }
  def self.limits
    @limits ||= T.let(LIMITS, T.nilable(T::Hash[Symbol, Integer]))
  end

  # Use custom rate limits for duration of the given block.
  #
  # custom_limits - A Hash of rate limit name Symbols and their corresponding
  #                 Integer values. Valid rate limit names are
  #                 :user_hour, :user_minute, :installation_hour, and
  #                 :installation_minute.
  #
  # Examples
  #
  #   use_custom_limits(:user_minute => 500, :user_hour => 500) do
  #     import_comments(comments, author: @current_user)
  #   end
  #
  # Returns nothing.
  sig { params(custom_limits: T::Hash[Symbol, Integer], blk: T.proc.void).void }
  def self.use_custom_limits(custom_limits, &blk)
    original_limits = limits
    @limits = limits.merge(custom_limits)
    yield
  ensure
    @limits = original_limits
  end

  # Disable content creation rate limits for the duration of the given block.
  #
  #     GitHub::RateLimitedCreation.disable_content_creation_rate_limits do
  #       ...
  #     end
  sig { params(blk: T.proc.returns(T.untyped)).returns(T.untyped) }
  def self.disable_content_creation_rate_limits(&blk)
    GitHub.content_creation_rate_limiting_enabled, orig =
      false, GitHub.content_creation_rate_limiting_enabled?
    yield
  ensure
    GitHub.content_creation_rate_limiting_enabled = orig
  end

  sig { params(skip_increment: T::Boolean).void }
  def check_creation_rate_limit(skip_increment: false)
    return true unless GitHub.content_creation_rate_limiting_enabled?
    return true unless new_record?

    increment_rate_creation_stat("checked", skip_increment: skip_increment)

    if apply_dynamic_rate_limit_configuration?
      GitHub::RateLimitedCreation.use_custom_limits(creation_rate_limit_configuration) do
        if creation_rate_limited?(skip_increment: skip_increment)
          errors.add :base, :rate_limited, message: ERROR_MESSAGE
        end
      end
    else
      if creation_rate_limited?(skip_increment: skip_increment)
        errors.add :base, :rate_limited, message: ERROR_MESSAGE
      end
    end
  end

  # This should be overridden by the including module to define dynamic custom
  # limits.
  #
  # The default implementation here provides no overrides, and so will cause
  # us to use the static rate limits defined in the `LIMITS` constant at the top
  # of this file.
  sig { returns(T::Hash[Symbol, Integer]) }
  def creation_rate_limit_configuration
    {}
  end

  # This should be overridden by the including module to rate limit using a custom user.
  sig { returns(T.nilable(User)) }
  def user_for_rate_limited_creation
    # In test, we sometimes validate rate-limited items that do not have a user
    # attached after the factory is done. This check for user existence
    # prevents exceptions during the validation step itself; if this happened
    # in "the real world" the nonexistent user will cause the item to be
    # invalid, and we'll let that validation take precedence.
    return T.unsafe(self).user if self.respond_to?(:user)
    nil
  end

  sig { params(skip_increment: T::Boolean).returns(T::Boolean) }
  def creation_rate_limited?(skip_increment: false)
    @creation_rate_limited ||= T.let({}, T.nilable(T::Hash[T::Boolean, T::Boolean]))
    if @creation_rate_limited.key?(skip_increment)
      return T.must(@creation_rate_limited[skip_increment])
    end

    if content_creation_rate_limit_allowlisted?
      return @creation_rate_limited[skip_increment] = false
    end

    @creation_rate_limited[skip_increment] =
      user_creation_rate_limit_exceeded?(skip_increment: skip_increment)
  end

  sig { returns(T::Boolean) }
  def content_creation_rate_limit_allowlisted?
    return true unless user = user_for_rate_limited_creation
    if user.content_creation_rate_limit_allowlisted?
      increment_rate_creation_stat("allowlisted")
      return true
    end
    false
  end

  sig { params(skip_increment: T::Boolean).returns(T::Boolean) }
  def user_creation_rate_limit_exceeded?(skip_increment: false)
    return false unless user = user_for_rate_limited_creation
    case user
    when Bot
      return false unless user.installation&.id.present?
      check_content_creation_time_rates :installation, user.installation.id,
                                        skip_increment: skip_increment
    when User
      check_content_creation_time_rates :user, user.id,
                                        skip_increment: skip_increment
    else
      T.absurd(user)
    end
  end

  sig { params(scope: Symbol, id: Integer, skip_increment: T::Boolean).returns(T::Boolean) }
  def check_content_creation_time_rates(scope, id, skip_increment: false)
    check_content_creation_minute_rate(scope, id, skip_increment: skip_increment) ||
      check_content_creation_hour_rate(scope, id, skip_increment: skip_increment)
  end

  # If using a custom rate limit, the including module may override this to set the name.
  sig { returns(T.nilable(String)) }
  def custom_create_rate_limit_name
    nil
  end

  sig { params(scope: Symbol, id: Integer, skip_increment: T::Boolean).returns(T::Boolean) }
  def check_content_creation_minute_rate(scope, id, skip_increment: false)
    limit_name = "#{scope}#{custom_create_rate_limit_name}_minute"
    check_content_creation_rate(id, 1.minute, 1.minute, limit_name, skip_increment: skip_increment)
  end

  sig { params(scope: Symbol, id: Integer, skip_increment: T::Boolean).returns(T::Boolean) }
  def check_content_creation_hour_rate(scope, id, skip_increment: false)
    limit_name = "#{scope}#{custom_create_rate_limit_name}_hour"
    if defined?(repository) && ignore_hourly_limit?(T.unsafe(self).repository)
      is_at_limit = check_content_creation_rate(id, 1.hour, 30.minutes, limit_name, skip_increment: true)
      increment_rate_creation_stat("ignored_hourly") if is_at_limit
      false
    else
      check_content_creation_rate(id, 1.hour, 30.minutes, limit_name, skip_increment: skip_increment)
    end
  end

  sig { params(id: Integer, ttl: Integer, ban_ttl: Integer, limit_name: String, skip_increment: T::Boolean).returns(T::Boolean) }
  def check_content_creation_rate(id, ttl, ban_ttl, limit_name, skip_increment: false)
    limit = T.must(GitHub::RateLimitedCreation.limits[limit_name.to_sym]) + 1
    key = GitHub::RateLimitedCreation.rate_key limit_name, id.to_s
    opt = {
      max_tries: limit,
      ttl: ttl,
      ban_ttl: ban_ttl,
      internal: true,
    }

    limiter = RedisRateLimiter.new(key, { max_tries: limit, ttl: ttl, ban_ttl: ban_ttl })
    result = skip_increment ? limiter.check : limiter.rate
    record_creation_rate_limit_stats(result, limit_name) if result.at_limit?
    result.at_limit?
  end

  sig { params(rate_limiter: RedisRateLimiter::Result, unit: String).void }
  def record_creation_rate_limit_stats(rate_limiter, unit)
    increment_rate_creation_stat("per_#{unit}")

    # REF https://github.com/github/ecosystem-apps/issues/356#issuecomment-472147849
    context_user = user_for_rate_limited_creation || User.new

    context = creation_rate_limit_log_context(context_user)
              .merge("#{unit}_rate".to_sym => rate_limiter.tries)

    log_context = semconvify_tags(context)
    GitHub.logger.info(log_context.merge(GitHub.context.to_hash))

    # Only create an audit log event on the first event that's over the threshold
    if rate_limiter.tries == rate_limiter.max_tries
      context_user.instrument AUDIT_LOG_EVENT_KEY, context
    end
  end

  sig { params(context_user: User).returns(T::Hash[Symbol, String]) }
  def creation_rate_limit_log_context(context_user)
    log_context_attributes = {
      rate_limited_creation: "#{self.class.to_s.underscore}",
      actor_id: context_user.id,
      actor: context_user.login,
    }

    if defined?(repository)
      log_context_attributes.merge(repo_id: T.unsafe(self).repository.id, repo: T.unsafe(self).repository.nwo)
    end

    log_context_attributes
  end

  sig { params(name: String, skip_increment: T::Boolean).void }
  def increment_rate_creation_stat(name, skip_increment: false)
    GitHub.dogstats.increment(
      "rate_limited_creation",
      tags: [
        "subject:#{self.class.to_s.underscore}",
        "name:#{name}",
        "config_type:#{apply_dynamic_rate_limit_configuration? ? "dynamic" : "static"}",
        "skip_increment:#{skip_increment}",
      ]
    )
  end

  # to be overridden by including models that are defining new dynamic rate limits
  sig { returns(T::Boolean) }
  def apply_dynamic_rate_limit_configuration?
    false
  end

  sig { params(klass: T::Class[T.anything]).void }
  def self.included(klass)
    klass.instance_eval do
      T.bind(self, T.class_of(ApplicationRecord::Base))
      validate :check_creation_rate_limit
    end
  end

  # The memcache/redis key name used for a rate limit
  sig { params(args: String).returns(String) }
  def self.rate_key(*args)
    (["rate_limited_creation"] + args).join "-"
  end

  private

  # Converts the log tags to SemConv standard. This exists because the tags are
  # also shared with the Audit log and we only want to change them in the
  # regular log.
  #
  # See: https://github.com/github/github/pull/270227
  sig { params(context: T::Hash[Symbol, String]).returns(T::Hash[Symbol, String]) }
  def semconvify_tags(context)
    unit = context.keys.find { |s| s.end_with?("_rate") }.to_s.chomp("_rate")
    {
      "gh.monolith_rate_limiter.unit": unit,
      "gh.monolith_rate_limiter.rate": context["#{unit}_rate".to_sym],
      "gh.monolith_rate_limiter.subject": context[:rate_limited_creation],
      "gh.actor.id": context[:actor_id],
      "gh.actor.login": context[:actor],
    }
  end

  sig { params(repo: Repository).returns(T::Boolean) }
  def ignore_hourly_limit?(repo)
    unless GitHub.flipper[:exempt_private_apps_from_hourly_content_creation_limits].enabled?(repo.organization)
      return false
    end

    return false if custom_create_rate_limit_name == Repository::RateLimitDependency::CUSTOM_CREATE_RATE_LIMIT_NAME

    user = user_for_rate_limited_creation

    unless user.is_a?(Bot)
      return false
    end

    repo.private? &&
      repo.organization.present? &&
      repo.organization == user.integration&.owner
  end
end
