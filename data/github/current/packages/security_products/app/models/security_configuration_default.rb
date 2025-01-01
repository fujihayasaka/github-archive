# typed: true
# frozen_string_literal: true

class SecurityConfigurationDefault < ApplicationRecord::Notify
  extend T::Sig

  include Instrumentation::Model

  belongs_to :security_configuration, inverse_of: :security_configuration_defaults
  belongs_to :target, polymorphic: true

  after_commit :instrument_default_configuration_change, on: [:update, :create]
  after_commit :instrument_default_configuration_delete, on: :destroy

  scope :for_organization, -> (o) { where(target: o) }
  scope :default_for_new_public_repos, -> { where(default_for_new_public_repos: true, default_for_new_private_repos: false) }
  scope :default_for_new_private_repos, -> { where(default_for_new_public_repos: false, default_for_new_private_repos: true) }
  scope :default_for_new_public_and_private_repos, -> { where(default_for_new_public_repos: true, default_for_new_private_repos: true) }

  sig do
    params(
      target: User,
      default_for_new_public_repos: T::Boolean,
      default_for_new_private_repos: T::Boolean,
      security_configuration_id: Integer,
    ).void
  end
  def self.create_or_update_defaults(
    target:,
    default_for_new_public_repos:,
    default_for_new_private_repos:,
    security_configuration_id:
  )
    defaults = for_organization(target)

    return if defaults.where(
      security_configuration_id:, default_for_new_public_repos:, default_for_new_private_repos:
    ).exists?

    ActiveRecord::Base.connected_to(role: :writing) do
      transaction do
        skip = false
        if default_for_new_public_repos && default_for_new_private_repos
          defaults.each(&:destroy!)
        elsif default_for_new_public_repos || default_for_new_private_repos
          defaults.default_for_new_public_repos.first&.destroy if default_for_new_public_repos
          defaults.default_for_new_private_repos.first&.destroy if default_for_new_private_repos

          default_record = defaults.default_for_new_public_and_private_repos.first
          if default_record.present?
            if default_record.security_configuration_id == security_configuration_id
              # When config A is the default for all repos,
              # and we change it to only be the default for either public or private repos,
              # then we can just update the existing record for the config with the given values.
              default_record.update(
                default_for_new_public_repos: default_for_new_public_repos,
                default_for_new_private_repos: default_for_new_private_repos
              )
            else
              # When config A is the default for all repos,
              # and we are setting config B as default for only either public or private repos,
              # then we update the existing record to be the default for the other type of repos.
              default_record.update(
                default_for_new_public_repos: !default_for_new_public_repos,
                default_for_new_private_repos: !default_for_new_private_repos
              )
            end
          end
        else
          defaults.find_by(target:, security_configuration_id:)&.destroy
          # In transactions, the usage of `return`, `break`, or `throw` is being deprecated and causes test failures.
          # Hence the usage of `skip` boolean value here, to skip creating/updating defaults if both defaults are false
          skip = true
        end

        unless skip
          default = find_or_initialize_by(target:, security_configuration_id:)
          # Even if the record is freshly initialized, `update` will persist it with the updated values:
          default.update(
            default_for_new_public_repos:,
            default_for_new_private_repos:
          )
        end
      end
    end
  end

  def instrument_default_configuration_change
    return if target.nil?
    instrument :update
  end

  def instrument_default_configuration_delete
    return if target.nil?
    instrument :delete
  end

  sig { returns(T::Hash[String, T.untyped]) }
  def event_payload
    {
      target: target,
      default_for_new_private_repos: default_for_new_private_repos,
      default_for_new_public_repos: default_for_new_public_repos,
      security_configuration_name: security_configuration&.name
    }.tap do |p|
      p[target.event_prefix] = target
    end
  end
end
