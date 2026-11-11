# typed: true
# frozen_string_literal: true

class SecurityConfigurationPolicy < ApplicationRecord::Notify
  class Enforcement < T::Enum
    enums do
      None = new
      Enforced = new
    end

    def to_s
      case self
      when Enforcement::None
        "none"
      when Enforcement::Enforced
        "enforced"
      else
        T.absurd(self)
      end
    end

    sig { params(value: Enforcement).returns(Integer) }
    def self.dump(value)
      case value
      when Enforcement::None
        0
      when Enforcement::Enforced
        1
      else
        T.absurd(value)
      end
    end

    sig { params(value: T.nilable(Integer)).returns(T.nilable(Enforcement)) }
    def self.load(value)
      case value
      when nil
        nil
      when 0
        Enforcement::None
      when 1
        Enforcement::Enforced
      else
        raise ArgumentError, "Invalid value for enforcement: #{value}"
      end
    end

    sig { params(value: T.nilable(String)).returns(T.nilable(Enforcement)) }
    def self.from_string(value)
      case value
      when nil
        nil
      when "not_enforced"
        Enforcement::None
      when "enforced"
        Enforcement::Enforced
      else
        raise ArgumentError, "Invalid value for enforcement: #{value}"
      end
    end
  end

  include Instrumentation::Model

  belongs_to :security_configuration, inverse_of: :security_configuration_policies
  belongs_to :target, polymorphic: true

  after_commit :instrument_policy_change, on: :update
  serialize :enforcement, coder: Enforcement, comparable: true
  scope :for_organization, -> (o) { where(target: o) }
  scope :enforced, -> { where(enforcement: Enforcement::Enforced) }
  scope :not_enforced, -> { where(enforcement: Enforcement::None) }

  sig do
    params(
      security_configuration_id: Integer,
      target: T.any(User, Business),
      enforcement: Enforcement,
    ).returns(SecurityConfigurationPolicy)
  end
  def self.create_or_update(security_configuration_id:, target:, enforcement:)
    ActiveRecord::Base.connected_to(role: :writing) do
      policy =
        find_or_create_by(security_configuration_id:, target:) do |new_policy|
          new_policy.enforcement = enforcement
        end
      policy.update!(enforcement: enforcement) if policy.enforcement != enforcement
      policy
    end
  end

  sig { returns(T::Boolean) }
  def enforced?
    enforcement == Enforcement::Enforced
  end

  def instrument_policy_change
    return if target.nil?
    instrument :update, target: target
  end

  def event_payload
    {
      target: target,
      enforcement: enforcement.to_s,
      security_configuration_name: security_configuration&.name
    }.tap do |p|
      p[target.event_prefix] = target
    end
  end
end
