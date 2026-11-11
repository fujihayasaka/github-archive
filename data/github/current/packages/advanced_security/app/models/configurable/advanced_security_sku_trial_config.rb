# typed: strict
# frozen_string_literal: true

# Instance-method facade over `EnterpriseCloudOnboard::AdvancedSecurityTrial`
# class methods, exposed on Business and Organization. Lets callers write
# `business.has_active_advanced_security_trial?` instead of the
# `EnterpriseCloudOnboard::AdvancedSecurityTrial.<method>(billable_entity: business, ...)`
# form.
#
# Mirrors the shape of `Configurable::AdvancedSecurityTrialConfig` (the legacy
# config-flag GHAS trial), but routes through the SKU trial implementation.
module Configurable
  module AdvancedSecuritySKUTrialConfig
    extend T::Helpers

    requires_ancestor { Configurable }
    requires_ancestor { ActiveRecord::Base }

    sig { returns(T::Boolean) }
    def has_active_advanced_security_trial?
      T.bind(self, T.any(Business, Organization))
      EnterpriseCloudOnboard::AdvancedSecurityTrial.has_active_advanced_security_trial?(billable_entity: self)
    end

    sig { params(actor: User).returns(T.nilable(Organization)) }
    def organization_for_advanced_security_trial(actor:)
      T.bind(self, T.any(Business, Organization))
      EnterpriseCloudOnboard::AdvancedSecurityTrial.organization_for_advanced_security_trial(billable_entity: self, actor: actor)
    end

    sig { returns(T.nilable(Date)) }
    def advanced_security_free_trial_ends_on
      T.bind(self, T.any(Business, Organization))
      EnterpriseCloudOnboard::AdvancedSecurityTrial.advanced_security_free_trial_ends_on(billable_entity: self)
    end

    sig { returns(T.nilable(Integer)) }
    def advanced_security_trial_days_left
      T.bind(self, T.any(Business, Organization))
      EnterpriseCloudOnboard::AdvancedSecurityTrial.advanced_security_trial_days_left(billable_entity: self)
    end

    sig { returns(T.nilable(Integer)) }
    def advanced_security_trial_duration_days
      T.bind(self, T.any(Business, Organization))
      EnterpriseCloudOnboard::AdvancedSecurityTrial.advanced_security_trial_duration_days(billable_entity: self)
    end

    sig { returns(T.nilable(Date)) }
    def advanced_security_trial_ended_at
      T.bind(self, T.any(Business, Organization))
      EnterpriseCloudOnboard::AdvancedSecurityTrial.trial_ended_at(billable_entity: self)
    end

    sig { returns(T::Hash[Symbol, T.nilable(Date)]) }
    def active_ghas_trials_data_for_entity
      T.bind(self, T.any(Business, Organization))
      EnterpriseCloudOnboard::AdvancedSecurityTrial.active_ghas_trials_data_for_entity(billable_entity: self)
    end

    sig { returns(T::Hash[Symbol, T.nilable(Date)]) }
    def active_ghas_trials_expiration
      T.bind(self, T.any(Business, Organization))
      EnterpriseCloudOnboard::AdvancedSecurityTrial.active_ghas_trials_expiration(billable_entity: self)
    end

    sig { returns(T::Array[Symbol]) }
    def active_ghas_trials
      T.bind(self, T.any(Business, Organization))
      EnterpriseCloudOnboard::AdvancedSecurityTrial.active_ghas_trials(billable_entity: self)
    end

    sig { returns(T::Boolean) }
    def advanced_security_free_trial_expired?
      T.bind(self, T.any(Business, Organization))
      EnterpriseCloudOnboard::AdvancedSecurityTrial.advanced_security_free_trial_expired?(billable_entity: self)
    end

    sig { returns(Integer) }
    def new_advanced_security_trial_days
      T.bind(self, T.any(Business, Organization))
      EnterpriseCloudOnboard::AdvancedSecurityTrial.new_advanced_security_trial_days(billable_entity: self)
    end

    sig { params(skip_shared_checks: T::Boolean).returns(T::Boolean) }
    def eligible_for_self_serve_advanced_security_trial?(skip_shared_checks: false)
      T.bind(self, T.any(Business, Organization))
      EnterpriseCloudOnboard::AdvancedSecurityTrial.eligible_for_self_serve_advanced_security_trial?(billable_entity: self, skip_shared_checks: skip_shared_checks)
    end

    sig { params(skip_shared_checks: T::Boolean).returns(T::Boolean) }
    def show_advanced_security_onboarding?(skip_shared_checks: false)
      T.bind(self, T.any(Business, Organization))
      EnterpriseCloudOnboard::AdvancedSecurityTrial.show_advanced_security_onboarding?(billable_entity: self, skip_shared_checks: skip_shared_checks)
    end

    sig { params(trial_type: Symbol).returns(EnterpriseCloudOnboard::SecretProtectionTrial) }
    def secret_protection_trial(trial_type: :ghas_stand_alone)
      T.bind(self, T.any(Business, Organization))
      EnterpriseCloudOnboard::AdvancedSecurityTrial.secret_protection_trial(billable_entity: self, trial_type: trial_type)
    end

    sig { params(trial_type: Symbol).returns(EnterpriseCloudOnboard::CodeSecurityTrial) }
    def code_security_trial(trial_type: :ghas_stand_alone)
      T.bind(self, T.any(Business, Organization))
      EnterpriseCloudOnboard::AdvancedSecurityTrial.code_security_trial(billable_entity: self, trial_type: trial_type)
    end

    sig { params(actor: User, trial_days: Integer, trial_source: Symbol).returns(GitHub::Result) }
    def enable_sku_based_trial(actor:, trial_days:, trial_source: :ghas_stand_alone)
      T.bind(self, T.any(Business, Organization))
      EnterpriseCloudOnboard::AdvancedSecurityTrial.enable_sku_based_trial(billable_entity: self, actor: actor, trial_days: trial_days, trial_source: trial_source)
    end

    sig { params(actor: User, is_stafftools_action: T::Boolean, purchase_unbundled_trial: T::Boolean).returns(GitHub::Result) }
    def end_advanced_security_trial(actor:, is_stafftools_action: false, purchase_unbundled_trial: false)
      T.bind(self, T.any(Business, Organization))
      EnterpriseCloudOnboard::AdvancedSecurityTrial.end_advanced_security_trial(billable_entity: self, actor: actor, is_stafftools_action: is_stafftools_action, purchase_unbundled_trial: purchase_unbundled_trial)
    end

    sig { params(actor: User, days: Integer, is_stafftools_action: T::Boolean).returns(GitHub::Result) }
    def extend_advanced_security_trial(actor:, days:, is_stafftools_action: false)
      T.bind(self, T.any(Business, Organization))
      EnterpriseCloudOnboard::AdvancedSecurityTrial.extend_advanced_security_trial(billable_entity: self, actor: actor, days: days, is_stafftools_action: is_stafftools_action)
    end
  end
end
