# typed: strict
# frozen_string_literal: true

class RepositoryLimit
  include GitHub::Memoizer
  include Instrumentation::Model

  SOFT_LIMIT = 50_000
  HARD_LIMIT = 100_000

  sig { returns(Users::IUser) }
  attr_reader :owner

  sig { params(owner: Users::IUser).void }
  def initialize(owner)
    @owner = T.let(owner, Users::IUser)
  end

  sig { returns(T::Boolean) }
  def enabled?
    owner.feature_enabled?(:repos_limits) && !GitHub.single_tenant_enterprise?
  end

  sig { params(soft: Integer, hard: Integer).void }
  def override(soft: soft_limit, hard: hard_limit)
    unless soft.between?(1, 2_000_000) && hard.between?(1, 2_000_000)
      raise ArgumentError, "Repository limits must be between 1 and 2 million"
    end
    unless soft < hard && soft < hard_limit
      raise ArgumentError, "Repository soft limit must be less than the hard limit"
    end

    if !overridden?
      instrument :create_override, owner: @owner, soft_limit: soft, hard_limit: hard
    else
      instrument :update_override, owner: @owner, soft_limit: soft, hard_limit: hard
    end


    Repositories::Kv.store.set(kv_key(owner_id), "#{soft}:#{hard}")
  end

  sig { void }
  def deliver_mail_later
    if at_hard_limit?
      RepositoryMailer.hard_limit_reached(owner).deliver_later
    elsif send_soft_limit_email?
      RepositoryMailer.soft_limit_reached(owner).deliver_later
    end
  end

  sig { returns(T::Boolean) }
  def overridden?
    Repositories::Kv.store.exists(kv_key(owner_id)).value { false }
  end

  sig { void }
  def reset_override
    instrument :reset_override, owner: @owner, soft_limit: SOFT_LIMIT, hard_limit: HARD_LIMIT

    Repositories::Kv.store.del(kv_key(owner_id))
  end

  sig { returns(Integer) }
  def soft_limit
    override_value.nil? ? SOFT_LIMIT : override_value&.split(":")&.first.to_i
  end

  sig { returns(T::Boolean) }
  def soft_limited?
    enabled? && !hard_limited? && count >= soft_limit
  end

  sig { returns(T::Boolean) }
  def at_soft_limit?
    enabled? && count == soft_limit
  end

  sig { returns(T::Boolean) }
  def send_soft_limit_email?
    return false unless enabled?
    return false unless soft_limited? && !hard_limited?

    # Send an email every 5k repos over the soft limit
    at_soft_limit? || count % 5000 == 0
  end

  sig { returns(Integer) }
  memoize def hard_limit
    override_value.nil? ? HARD_LIMIT : override_value&.split(":")&.last.to_i
  end

  sig { returns(T::Boolean) }
  def hard_limited?
    enabled? && count >= hard_limit
  end

  sig { returns(T::Boolean) }
  def at_hard_limit?
    enabled? && count == hard_limit
  end

  sig { void }
  def instrument_limit_warning
    payload = {
      limit: hard_limit,
      count: count,
      owner: @owner,
    }

    if @owner.is_a?(Organization)
      payload[:org] = @owner
      payload[:org_id] = @owner.id
    end

    instrument :warning, payload
  end

  sig { void }
  def instrument_limit_reached
    payload = {
      limit: hard_limit,
      count: count,
      owner: @owner,
    }

    if @owner.is_a?(Organization)
      payload[:org] = @owner
      payload[:org_id] = @owner.id
    end

    instrument :reached, payload
  end

  sig { returns(Integer) }
  memoize def count
    Repository.active.where(owner_id: owner_id).count
  end

  private

  sig { returns(T.nilable(String)) }
  memoize def override_value
    Repositories::Kv.store.get(kv_key(owner_id)).value { nil }
  end

  sig { returns(Integer) }
  def owner_id
    T.must(owner.id)
  end

  sig { params(owner_id: Integer).returns(String) }
  def kv_key(owner_id)
    "repo_hard_limit_override.v1.#{owner_id}"
  end
end
