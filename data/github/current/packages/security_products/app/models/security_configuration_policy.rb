# typed: true
# frozen_string_literal: true

class SecurityConfigurationPolicy < ApplicationRecord::Notify
  extend T::Sig

  include Instrumentation::Model

  belongs_to :security_configuration, inverse_of: :security_configuration_policies
  belongs_to :target, polymorphic: true

  after_commit :instrument_policy_change, on: :update

  enum :enforcement, { not_enforced: 0, enforced: 1 }
  scope :for_organization, -> (o) { where(target: o) }

  sig do
    params(
      security_configuration_id: Integer,
      target: User,
      enforcement: Symbol,
    ).returns(SecurityConfigurationPolicy)
  end
  def self.create_or_update(security_configuration_id:, target:, enforcement:)
    ActiveRecord::Base.connected_to(role: :writing) do
      policy =
        find_or_create_by(security_configuration_id:, target:) do |new_policy|
          new_policy.enforcement = enforcement
        end

      policy.enforcement = enforcement
      policy.enforcement_changed? && policy.save!
      policy
    end
  end

  def instrument_policy_change
    return if target.nil?
    instrument :update, target: target
  end

  def event_payload
    {
      target: target,
      enforcement: enforcement,
      security_configuration_name: security_configuration&.name
    }.tap do |p|
      p[target.event_prefix] = target
    end
  end
end
