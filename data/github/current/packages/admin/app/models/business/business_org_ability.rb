# typed: strict
# frozen_string_literal: true

# Creating a lot of in memory Ability objects is very slow.
# We don't need the full specification for business org abilities.
# We still want to be able to pluck from an array so declaring a type with a single [] operator for pluck.
class Business::BusinessOrgAbility
  include Comparable

  sig { returns(Integer) }
  attr_reader :actor_id

  sig { returns(String) }
  attr_reader :actor_type

  sig { returns(Integer) }
  attr_reader :subject_id

  sig { returns(String) }
  attr_reader :subject_type

  sig { returns(String) }
  attr_reader :action

  sig do
    params(
      actor_id: Integer,
      actor_type: String,
      subject_id: Integer,
      subject_type: String,
      action: String
    ).void
  end
  def initialize(actor_id:, actor_type:, subject_id:, subject_type:, action:)
    @actor_id = actor_id
    @actor_type = actor_type
    @subject_id = subject_id
    @subject_type = subject_type
    @action = action
  end

  sig { params(key: T.any(Symbol, String)).returns(T.untyped) }
  def [](key)
    # Linter doesn't like public_send, so hardcode the mappings, this will be faster anyway.
    case key.to_sym
    when :actor_id then actor_id
    when :actor_type then actor_type
    when :subject_id then subject_id
    when :subject_type then subject_type
    when :action then action
    else
      raise ArgumentError, "Unknown key: #{key.inspect}"
    end
  end

  sig { params(other: Object).returns(T.nilable(Integer)) }
  def <=>(other)
    return nil unless other.is_a?(self.class)
    [actor_id, actor_type, subject_id, subject_type, action] <=> [other.actor_id, other.actor_type, other.subject_id, other.subject_type, other.action]
  end

  sig { params(user_id: Integer, org_id: Integer).returns(Business::BusinessOrgAbility) }
  def self.from_user_org(user_id:, org_id:)
    self.new(
      actor_id: user_id,
      actor_type: "User",
      subject_id: org_id,
      subject_type: "Organization",
      action: "read",
    )
  end
end
