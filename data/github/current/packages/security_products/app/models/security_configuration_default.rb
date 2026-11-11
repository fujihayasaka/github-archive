# typed: true
# frozen_string_literal: true

class SecurityConfigurationDefault < ApplicationRecord::Notify

  include Instrumentation::Model

  belongs_to :security_configuration, inverse_of: :security_configuration_defaults
  belongs_to :target, polymorphic: true

  after_commit :instrument_default_configuration_change, on: [:update, :create]
  after_commit :instrument_default_configuration_delete, on: :destroy

  scope :for_target, -> (o) { where(target: o) }
  scope :default_for_new_public_repos, -> { where(default_for_new_public_repos: true, default_for_new_private_repos: false) }
  scope :default_for_new_private_repos, -> { where(default_for_new_public_repos: false, default_for_new_private_repos: true) }
  scope :default_for_new_public_and_private_repos, -> { where(default_for_new_public_repos: true, default_for_new_private_repos: true) }

  # Helper to return defaults in order of priority. In practice, this means organization defaults will supersede enterprise defaults.
  scope :in_priority_order, -> { order(Arel.sql("FIELD(target_type, 'User') DESC")) }

  # Helper method to find a SecurityConfigurationDefault which takes into account org- and enterprise-level defaults.
  #
  #   target (Organization / Business) - Which entity you're finding the default for. If an Organization is provided,
  #     we will also find relevant enterprise-level defaults. If a Business is provided, we'll only return their defaults.
  #   visibility (:public / :private) - What type of repo default are you looking for.
  #
  sig { params(target: T.any(User, Business), visibility: Symbol).returns(T::Array[SecurityConfigurationDefault]) }
  def self.find_for(target:, visibility:)
    raise ArgumentError, "visibility must be :public, :private or :all" unless visibility.in?([:public, :private, :all])

    targets = [target]
    if target.is_a?(User)
      targets << target.business if target.business
    end

    defaults = in_priority_order.where(target: targets).to_a
    defaults.uniq(&:security_configuration_id).select do |d|
      if visibility == :all
        d.default_for_new_public_repos == true || d.default_for_new_private_repos == true
      elsif visibility == :public
        d.default_for_new_public_repos == true
      elsif visibility == :private
        d.default_for_new_private_repos == true
      end
    end
  end

  # Return the default public and private SecurityConfiguration IDs for the target.
  #   If the target is an Organizaiton we will find org *and* enterprise defaults.
  #   If the target is a Business we will only find enterprise level defaults.
  #
  # Returns a Hash: { default_for_new_public_repos: 1234, default_for_new_private_repos: 9876 }
  sig { params(target: T.any(User, Business)).returns(T::Hash[Symbol, T.nilable(Integer)]) }
  def self.default_security_configuration_ids_for(target)
    targets = if target.is_a?(Organization)
      [target, target.business].compact
    else
      target
    end

    defaults = in_priority_order.where(target: targets).to_a
    return { default_for_new_public_repos: nil, default_for_new_private_repos: nil } if defaults.blank?

    # Ensure there is only one default per SecurityConfiguration ID, that way if an org overrides an enterprise
    # default we won't let the Business SecurityConfigurationDefault record be there when we use `find` below:
    defaults.uniq!(&:security_configuration_id)

    {
      default_for_new_public_repos:  defaults.find(&:default_for_new_public_repos)&.security_configuration_id,
      default_for_new_private_repos: defaults.find(&:default_for_new_private_repos)&.security_configuration_id,
    }
  end

  sig do
    params(
      target: T.any(User, Business),
      default_for_new_public_repos: T::Boolean,
      default_for_new_private_repos: T::Boolean,
      security_configuration: SecurityConfiguration,
    ).void
  end
  def self.create_or_update_defaults(
    target:,
    default_for_new_public_repos:,
    default_for_new_private_repos:,
    security_configuration:
  )
    defaults = for_target(target)
    security_configuration_id = security_configuration.id

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
          # If the configuration belongs to an organization, we can destroy the defaults and skip creating a new one
          # for cases where the default is not set.
          #
          # However, if the configuration belongs to an enterprise and we're setting a default for an organization,
          # we need to create a record with the defaults set to false for both public & private,
          # which means we can not skip record updating like we do with org-level configs.
          unless security_configuration.belongs_to_enterprise? && target.is_a?(Organization)
            defaults.find_by(target:, security_configuration_id:)&.destroy
            # In transactions, the usage of `return`, `break`, or `throw` is being deprecated and causes test failures.
            # Hence the usage of `skip` boolean value here, to skip creating/updating defaults if both defaults are false
            skip = true
          end
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
