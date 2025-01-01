# typed: strict
# frozen_string_literal: true

module User::RateLimitAllowlistingDependency
  extend T::Sig
  extend T::Helpers
  extend ActiveSupport::Concern
  include AuditLogHelper

  requires_ancestor { User }

  included do
    T.bind(self, T.class_of(User))

    has_one :user_whitelisting, dependent: :destroy
    has_many :user_whitelistings, as: :whitelister
  end


  alias_attribute :user_allowlisting, :user_whitelisting
  # Public: Returns whether or not this user can bypass content creation rate limits
  sig { returns(T::Boolean) }
  def content_creation_rate_limit_allowlisted?
    !user_whitelisting.nil? || temporarily_content_creation_allowlisted?
  end

  # Public: Toggle this user's rate limit allowlist status.
  #
  # See #content_creation_rate_limit_allowlist for a description of arguments, which will be
  # passed through.
  sig { params(allowlister: ::User).void }
  def toggle_content_creation_rate_limit_allowlisted(allowlister:)
    if content_creation_rate_limit_allowlisted?
      content_creation_rate_limit_deallowlist!(allowlister: allowlister)
    else
      content_creation_rate_limit_allowlist!(allowlister: allowlister)
    end
  end

  # Public: Temporarily allow this user to create content without limits.
  sig { params(allowlister: ::User, duration: ActiveSupport::Duration).void }
  def temporarily_allowlist_content_creation(allowlister:, duration: 3.days)
    key = content_creation_temporary_rate_limit_key
    content = [allowlister.id, Time.now.to_i].join(":")
    Billing::Kv.store.set(key, content, expires: duration.from_now)
    instrument :rate_limit_allowlist, \
      prefix: :staff,
      user: self,
      actor: allowlister,
      temporary: true
  end

  # Public. The user that temporarily allowlisted this user.
  sig { returns(::User) }
  def temporary_content_creation_allowlisting_user
    # It should be used with `temporarily_content_creation_allowlisted?` to guarantee non-nil value
    User.find(T.must(temporary_content_creation_allowlist_info.to_s.split(":").first))
  end

  # Public. When this user was temporarily allowlisted.
  sig { returns(Time) }
  def temporary_content_creation_allowlisted_at
    Time.at(temporary_content_creation_allowlist_info.to_s.split(":").last.to_i)
  end

  # Public: Determine if this user is temporarily content creation allowlisted.
  sig { returns(T::Boolean) }
  def temporarily_content_creation_allowlisted?
    !!temporary_content_creation_allowlist_info
  end

  # Stored information in GitHub::KV about temporary content creation limits
  sig { returns(T.nilable(String)) }
  private def temporary_content_creation_allowlist_info
    return @_temporarily_allowlisted_content if defined?(@_temporarily_allowlisted_content)

    # If KV is unavailable, return nil. While KV is unavailable, we will treat
    # all users as if they are NOT temporarily allowlisted.
    @_temporarily_allowlisted_content = T.let(
      ActiveRecord::Base.connected_to(role: :reading) do
        Billing::Kv.store.get(content_creation_temporary_rate_limit_key).value { nil }
      end, T.nilable(String))
  end

  # GitHub::KV key for temporary rate limits.
  sig { returns(String) }
  private def content_creation_temporary_rate_limit_key
    ["rate_limited_creation", "temporary_allowlist", self.id].join ":"
  end

  # Public: Remove this user from the allowlist.
  sig { params(allowlister: ::User).void }
  def content_creation_rate_limit_deallowlist!(allowlister:)
    user_whitelisting.try(:destroy)
    Billing::Kv.store.del(content_creation_temporary_rate_limit_key)
    instrument :rate_limit_deallowlist, \
      prefix: :staff,
      user: self,
      actor: allowlister
  end

  # Public: Add this user to the allowlist.
  #
  #   allowlister: The staff User adding this user to the allowlist
  sig { params(allowlister: ::User).void }
  def content_creation_rate_limit_allowlist!(allowlister:)
    self.create_user_whitelisting(whitelister: allowlister)
    instrument :rate_limit_allowlist, \
      prefix: :staff,
      user: self,
      actor: allowlister,
      temporary: false
  end

  # Public: Returns when this user was allowlisted
  sig { returns(T.nilable(Time)) }
  def content_creation_rate_limit_allowlisted_at
    user_whitelisting.try(:created_at)
  end

  # Public: Returns the user who allowlisted this user
  sig { returns(T.nilable(::User)) }
  def content_creation_rate_limit_allowlister
    user_whitelisting.try(:whitelister)
  end

  # Public: Return the audit log event from the last time
  # this user was blocked due to submitting content too quickly.
  sig { returns(T.nilable(AuditLogEntry)) }
  def last_content_creation_rate_limit_violation
    query = {
      allowlist: ["user.creation_rate_limit_exceeded"],
      actor_id: self.id,
      limit: 1,
    }
    res = Audit::Driftwood::Query.new_user_query(query).execute.results.first
    return unless res
    AuditLogEntry.new_from_hash(res)
  end
end
