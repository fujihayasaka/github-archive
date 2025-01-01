# typed: true
# frozen_string_literal: true

module OnboardingTasks
  class Onboard

    ALL = [
      Businesses::InviteAdmin,
      Businesses::CreateOrganization,
      Businesses::EnableSaml,
      Organizations::AutoAssignIssue,
      Organizations::BranchProtectionRule,
      Organizations::CreateCodespace,
      Organizations::OpenPullRequest,
      Organizations::CustomizePermission,
      Organizations::DependabotSecurityUpdates,
      Organizations::DependabotVulnerabilityAlerts,
      Organizations::EnableSaml,
      Organizations::InviteMember,
      Organizations::PublishWebsite,
      Organizations::RunCi,
    ].freeze
    ALL_BY_CONTEXT = ALL.group_by { |task| task.context }

    FREE_TASKS = [
      Organizations::InviteMember,
      Organizations::CustomizePermission,
      Organizations::OpenPullRequest,
      Organizations::BranchProtectionRule,
      Organizations::AutoAssignIssue,
      Organizations::RunCi,
    ].freeze

    TEAM_TASKS = [
      Organizations::CreateCodespace,

      *FREE_TASKS,
    ].freeze

    GHEC_TASKS = [
      Organizations::EnableSaml,
      Organizations::DependabotSecurityUpdates,
      Organizations::DependabotVulnerabilityAlerts,
      Organizations::PublishWebsite,

      *TEAM_TASKS,
    ].freeze

    def initialize(taskable, user)
      @taskable = taskable
      @user = user
    end

    def self.percentage_completed(taskable, context)
      ((taskable.completed_onboarding_tasks.size.to_f / ALL_BY_CONTEXT[context].size) * 100).round(2)
    end

    def self.next_uncompleted_task_for_context(taskable, user, context)
      uncompleted_task = ALL_BY_CONTEXT[context]&.find do |task_class|
        task = task_class.new(user: user, taskable: taskable)
        task.enabled_for_user? && task.enabled_for_plan? && !taskable.completed_onboarding_tasks.include?(task.task_key)
      end

      uncompleted_task&.new(taskable: taskable, user: user)
    end

    def self.remaining_tasks(taskable, user, context)
      return [] unless ALL_BY_CONTEXT[context]

      ALL_BY_CONTEXT[context].map(&:task_key) - taskable.completed_onboarding_tasks
    end

    def task(task_key:, context:, attributes: {})
      task_class = ALL_BY_CONTEXT[context].find { |task| task.task_key == task_key.to_sym }
      return nil unless task_class
      task_class.new(taskable: @taskable, user: @user, attributes: attributes)
    end
  end
end
