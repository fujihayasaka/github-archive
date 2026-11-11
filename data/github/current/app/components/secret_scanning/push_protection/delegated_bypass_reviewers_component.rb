# typed: strict
# frozen_string_literal: true

module SecretScanning::PushProtection
  # View component for Secret Scanning - Delegated Bypass Reviewers
  class DelegatedBypassReviewersComponent < ApplicationComponent

    sig do
      params(
        source: T.any(Repository, Organization, Business),
        current_user: User,
        enabled: T::Boolean,
        config_enabled: T::Boolean,
        config_disabled: T::Boolean,
        update_path: String,
        add_reviewers_path: String,
        update_reviewers_path: String,
        remove_reviewers_path: String,
        suggested_reviewers_path: String,
      ).void
    end
    def initialize(source:, current_user:, enabled:, config_enabled:, config_disabled:, update_path:, add_reviewers_path:, update_reviewers_path:, remove_reviewers_path:, suggested_reviewers_path:)
      @source = source
      @current_user = current_user
      @delegated_bypass_enabled = enabled
      @config_enabled = config_enabled
      @config_disabled = config_disabled
      @update_path = update_path
      @add_reviewers_path = add_reviewers_path
      @update_reviewers_path = update_reviewers_path
      @remove_reviewers_path = remove_reviewers_path
      @suggested_reviewers_path = suggested_reviewers_path
    end

    # deprecated: remove when we remove the secret_scanning_push_protection_exempt_repos FF
    sig { returns(T::Array[T::Hash[T.untyped, T.untyped]]) }
    memoize def current_reviewers
      bypass_reviewers = get_bypass_reviewers
      return [] if bypass_reviewers.empty?

      bypass_reviewers.map do |reviewer|
        SecretScanning::Services::DelegatedBypassService.ui_bypass_reviewer_hash(reviewer)
      end
    end

    sig { returns(T::Array[T::Hash[T.untyped, T.untyped]]) }
    memoize def current_actors
      bypass_reviewers = get_bypass_reviewers
      return [] if bypass_reviewers.empty?

      bypass_reviewers.map do |reviewer|
        SecretScanning::Services::DelegatedBypassService.security_config_bypass_actor_hash(reviewer)
      end
    end

    sig { returns(T.nilable(String)) }
    memoize def human_readable_security_configuration_target_type
      # This method is only relevant for repos, so that we can display at what level the security configuration is set.
      return nil unless @source.is_a?(Repository)

      # The only relevant targets here are Business and Organization
      case @source.security_configuration&.target_type
      when "Business"
        "enterprise"
      when "User"
        return "organization" if @source.security_configuration&.target.is_a?(Organization)
        nil
      else
        nil
      end
    end

    sig { returns(Integer) }
    def teams_count
      type_count(SecretScanning::Services::DelegatedBypassService::TEAM_REVIEWER_TYPES)
    end

    sig { returns(Integer) }
    def roles_count
      type_count(SecretScanning::Services::DelegatedBypassService::ROLE_REVIEWER_TYPES)
    end

    sig { returns(Integer) }
    def integrations_count
      type_count(SecretScanning::Services::DelegatedBypassService::INTEGRATION_REVIEWER_TYPES)
    end

    private

    sig { returns T.any(Repository, Organization, Business) }
    attr_reader :source

    sig { returns User }
    attr_reader :current_user

    sig { returns T::Boolean }
    attr_reader :delegated_bypass_enabled

    sig { returns T::Boolean }
    attr_reader :config_enabled

    sig { returns T::Boolean }
    attr_reader :config_disabled

    sig { returns String }
    attr_reader :update_path

    sig { returns String }
    attr_reader :add_reviewers_path

    sig { returns String }
    attr_reader :update_reviewers_path

    sig { returns String }
    attr_reader :remove_reviewers_path

    sig { returns String }
    attr_reader :suggested_reviewers_path

    sig { returns Symbol }
    def enablement_selection
      @delegated_bypass_enabled ? :delegated_bypass_enabled : :delegated_bypass_disabled
    end

    sig { returns T.nilable(String) }
    def enablement_display_option
      delegated_bypass_choices[enablement_selection]
    end

    sig { returns T::Hash[Symbol, String] }
    def delegated_bypass_choices
      {
        delegated_bypass_disabled: "Anyone with write access",
        delegated_bypass_enabled: "Specific roles or teams",
      }
    end

    sig { returns(T::Hash[String, Symbol]) }
    def role_icon_map
      {
        Write: :pencil,
        Maintain: :tools,
        'Repository admin': :eye,
        'Organization admin': :eye,
        'Enterprise owner': :people,
      }
    end

    sig { returns(T::Hash[String, Symbol]) }
    def dotcom_to_tss_reviewer_type
      {
        RepositoryRole:    :ROLE,
        OrganizationAdmin: :ROLE,
        Team:              :TEAM,
      }
    end

    sig { params(types: T::Set[Symbol]).returns(Integer) }
    def type_count(types)
      count = 0
      current_reviewers.each do |reviewer|
        count += 1 if types.include?(reviewer[:reviewer_type])
      end
      count
    end

    sig { returns(T::Array[T::Hash[T.untyped, T.untyped]]) }
    def suggested_bypass_reviewers
      SecretScanning::Services::DelegatedBypassService.suggested_bypass_reviewers(@source, @current_user, params)
    end

    sig { returns(T::Array[T::Hash[T.untyped, T.untyped]]) }
    memoize def enabled_bypass_actors
      filtered = []
      suggested_bypass_reviewers.each do |suggestion|
        current_reviewers.each do |compare|
          if suggestion[:actorId] == compare[:actor_id] && compare[:reviewer_type] == dotcom_to_tss_reviewer_type[suggestion[:actorType]]
            filtered.push(suggestion)
          end
        end
      end
      filtered
    end

    sig { returns(T::Array[SecretScanning::Models::BypassReviewer]) }
    memoize def get_bypass_reviewers
      bypass_reviewers, error_message = SecretScanning::Services::DelegatedBypassService.get_bypass_reviewers(source, @current_user.id)
      if bypass_reviewers.nil? || bypass_reviewers.empty? || error_message
        return []
      end

      bypass_reviewers
    end
  end
end
