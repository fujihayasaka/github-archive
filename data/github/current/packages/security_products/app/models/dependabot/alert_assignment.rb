# typed: strict
# frozen_string_literal: true

module Dependabot
  class AlertAssignment < ApplicationRecord::Notify
    ASSIGNEE_LIMIT = 10
    AVAILABLE_ASSIGNEES_LIMIT = 1000

    self.table_name = "repository_vulnerability_alert_assignments"

    belongs_to :repository_vulnerability_alert, inverse_of: :alert_assignments
    belongs_to :user

    validates :repository_vulnerability_alert_id, presence: true
    validates :user_id, presence: true, uniqueness: { scope: [:repository_vulnerability_alert_id] }
    validate :assignee_limit_not_exceeded, on: :create
    validate :assignee_permitted, on: [:create, :update]

    # Returns users who can be assigned to Dependabot alerts for a repository.
    # Limit defaults to AVAILABLE_ASSIGNEES_LIMIT. Filtering is required because
    # available_assignee_ids returns users with read access, but we need resolve permission.
    # Query is an optional text string used to filter users by their login or profile name.
    sig { params(repository: Repository, current_user: User, limit: Integer, query: T.nilable(String)).returns(T::Array[User]) }
    def self.available_assignees(repository:, current_user:, limit: AVAILABLE_ASSIGNEES_LIMIT, query: nil)
      ids = repository.available_assignee_ids(limit: Issue::AssignmentDependency::PLATFORM_ASSIGNEE_LIMIT)

      includes_associations = [:profile]
      includes_associations << :business_user_accounts if GitHub.multi_tenant_enterprise?

      tenant_id = GitHub::CurrentTenant.get.try(:id) || User::MultiTenantEnterpriseManagedDependency::NON_ENTERPRISE_MANAGED_BUSINESS_ID
      scope = User.where(id: ids, business_id: tenant_id).includes(includes_associations)
      scope = scope.order("display_login").filter_spam_for(current_user)

      if query.present?
        scope = scope.like_display_login_or_profile_name(query.strip)
      end

      scope.limit(limit).select do |user|
        repository.can_resolve_vulnerability_alerts?(user)
      end
    end

    private

    sig { void }
    def assignee_limit_not_exceeded
      alert = repository_vulnerability_alert
      return unless alert

      count = alert.alert_assignments.size # includes in-memory changes not yet persisted to the database
      # #create validates before adding the new record to the in-memory collection. #build validates after adding the new record to the in-memory collection.
      count += 1 unless alert.alert_assignments.include?(self)
      if count > ASSIGNEE_LIMIT
        errors.add(:base, "Cannot have more than #{ASSIGNEE_LIMIT} assignees")
      end
    end

    sig { void }
    def assignee_permitted
      # these two assignments are necessary because Sorbet can't infer types correctly without them
      alert = repository_vulnerability_alert
      assignee = user

      # Other validations will catch missing alert or user, but even if they error it won't stop this validation from
      # running... so without this guard, this validation could unexpectedly blow up.
      return unless alert && assignee

      permitted = assignee.is_a?(Bot) ? bot_permitted?(alert) : T.must(alert.repository).can_resolve_vulnerability_alerts?(assignee)
      errors.add(:user, "#{assignee.display_login} is not permitted to be assigned to this alert") unless permitted
    end

    sig { params(alert: RepositoryVulnerabilityAlert).returns(T::Boolean) }
    def bot_permitted?(alert)
      bot = T.cast(user, Bot)
      return false if bot.integration.nil?

      copilot_swe_agent_integration = ::Apps::Privileged.integration(:copilot_swe_agent)
      if bot.integration == copilot_swe_agent_integration
        # Copilot support will be added in the future
        return false
      end

      unless ::Apps::Privileged.capable?(:is_assignable, app: bot.integration)
        return false
      end

      unless ::Apps::Privileged.capable?(:installed_globally, app: bot.integration)
        # If the bot is not installed globally, verify it has access to this repository
        return false unless IntegrationInstallation.with_repository(alert.repository).where(integration: bot.integration).exists?
      end

      true
    end
  end
end
