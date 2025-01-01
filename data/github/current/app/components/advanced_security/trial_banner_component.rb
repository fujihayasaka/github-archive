# typed: strict
# frozen_string_literal: true

module AdvancedSecurity
  class TrialBannerComponent < ApplicationComponent
    include ApplicationComponent::Rescuable

    rescue_from StandardError, with: :nothing

    sig { returns T::Hash[Symbol, T.untyped] }
    attr_reader :system_arguments

    sig { returns T.any(Business, Organization) }
    attr_reader :billable_entity

    sig { returns T.nilable(User) }
    attr_reader :user

    sig do
      params(
        user: T.nilable(User),
        billable_entity: T.any(Business, Organization),
        organization: T.nilable(Organization),
        system_arguments: Primer::SystemArgumentsValue
      ).void
    end
    def initialize(user:, billable_entity:, organization: nil, **system_arguments)
      @user = user
      @billable_entity = billable_entity
      @organization = organization
      @system_arguments = system_arguments
      @system_arguments[:display] = [:block, nil, :flex, nil, nil] unless @system_arguments.key?(:display)
      @system_arguments[:align_items] = :center unless @system_arguments.key(:align_items)
      @system_arguments[:justify_content] = :space_between unless @system_arguments.key?(:justify_content)
      @system_arguments[:py] = 2 unless @system_arguments.key?(:py)
      @system_arguments[:px] = [3, nil, 4, 5, nil] unless @system_arguments.key?(:px)
      @system_arguments[:font_size] = 6 unless @system_arguments.key?(:font_size)
      @system_arguments[:bg] = :accent unless @system_arguments.key?(:accent)
    end

    sig { returns(T::Boolean) }
    def render?
      return false unless @user
      return false unless GitHub.billing_enabled?

      if @billable_entity.is_a?(Business)
        return false if @billable_entity.trial?
      end
      return false unless can_manage_business || can_manage_organization

      active_ghas_trials.any?
    end

    private

    sig { returns(String) }
    def banner_text_long
      active_ghas_trials
        .map { |trial| [trial, trial_days_left(trial)] }
        .sort_by { |_, days_left| days_left }
        .map do |trial, days_left|
          "#{pluralize(days_left, "day")} left on GitHub #{trial_title(trial)} trial"
        end.to_sentence + "."
    end

    sig { returns(T::Array[String]) }
    def banner_text_short
      active_ghas_trials
        .map { |trial| [trial, trial_days_left(trial)] }
        .sort_by { |_, days_left| days_left }
        .map do |trial, days_left|
          "#{pluralize(days_left, "day")} left on GitHub #{trial_title(trial)} trial."
        end
    end

    sig { params(trial: Symbol).returns(Integer) }
    def trial_days_left(trial)
      case trial
      when :dfd_self_serve_trial
        advanced_security_trial_days_left
      when :secret_protection_trial
        sales_led_trial_days_left(secret_protection_trial)
      when :code_security_trial
        sales_led_trial_days_left(code_security_trial)
      else
        0
      end
    end

    sig { params(trial: Symbol).returns(String) }
    def trial_title(trial)
      case trial
      when :dfd_self_serve_trial
        "Advanced Security"
      when :secret_protection_trial
        "Secret Protection"
      when :code_security_trial
        "Code Security"
      else
        ""
      end
    end

    sig { returns(T::Array[Symbol]) }
    memoize def active_ghas_trials
      trials = []

      if @billable_entity.is_a?(Business)
        trials << :dfd_self_serve_trial if @billable_entity.has_active_advanced_security_trial?
      end

      # Can just delete this line when feature flag is removed
      return trials unless FeatureFlag.vexi.enabled?(:ghas_enable_trial_access_for_existing_users, @billable_entity, default: false)

      trials << :secret_protection_trial if secret_protection_trial&.enabled? && T.must(secret_protection_trial&.expires_at) > DateTime.now
      trials << :code_security_trial if code_security_trial&.enabled? && T.must(code_security_trial&.expires_at) > DateTime.now

      trials
    end

    sig { returns(T::Boolean) }
    memoize def can_self_serve_trial?
      active_ghas_trials.include?(:dfd_self_serve_trial)
    end

    sig { returns(T.nilable(EnterpriseCloudOnboard::SecretProtectionTrial)) }
    memoize def secret_protection_trial
      EnterpriseCloudOnboard::SecretProtectionTrial.new(billable_entity: @billable_entity)
    end

    sig { returns(T.nilable(EnterpriseCloudOnboard::CodeSecurityTrial)) }
    memoize def code_security_trial
      EnterpriseCloudOnboard::CodeSecurityTrial.new(billable_entity: @billable_entity)
    end

    sig { returns(Integer) }
    memoize def advanced_security_trial_days_left
      return 0 unless @billable_entity.is_a?(Business)
      @billable_entity.advanced_security_subscription_item&.days_left_on_free_trial || 0
    end

    sig { params(trial: T.nilable(EnterpriseCloudOnboard::SKUTrial)).returns(Integer) }
    def sales_led_trial_days_left(trial)
      return 0 unless trial
      return 0 unless trial.enabled?

      since_trial_started = (DateTime.now - T.must(trial.started_at)).days
      (trial.number_of_days&.days - since_trial_started).in_days.ceil.to_i
    end

    sig { returns(T::Boolean) }
    memoize def can_manage_business
      @billable_entity.adminable_by?(@user)
    end

    sig { returns(T::Boolean) }
    memoize def can_manage_organization
      return false unless org = organization
      org.adminable_by?(@user)
    end

    sig { returns(T.nilable(Organization)) }
    memoize def organization
      if @billable_entity.is_a?(Business)
        @organization || @billable_entity.organization_for_advanced_security_trial(actor: T.must(user))
      else
        @billable_entity
      end
    end
  end
end
