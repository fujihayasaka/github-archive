# typed: true
# frozen_string_literal: true

class OrganizationOnboarding::DemoRepositoriesController < OrganizationOnboarding::ApplicationController
  before_action :non_emu_required

  DEMO_CREATION_EXCEPTIONS = [
    ActiveRecord::NotNullViolation,
    ActiveRecord::RecordNotUnique,
    Git::Ref::RepositoryRuleViolationError,
    Orchestration::Error,
    OrganizationOnboard::DemoRepository::FailedRepositoryCreationError,
  ]

  def create
    OrganizationOnboard::DemoRepository.new(organization: this_organization).setup(current_user)

    task = OnboardingTasks::Onboard.new(this_organization, current_user).task(task_key: params[:task].to_sym, context: :organizations)
    GitHub.dogstats.increment("organization.created_demo_repo", tags: ["status:success"])

    redirect_to task.task_link
  rescue *DEMO_CREATION_EXCEPTIONS => error
    Failbot.report error
    GitHub.dogstats.increment("organization.created_demo_repo", tags: ["status:error"])
    flash[:error] = "The demo repository for your task could not be created. Please try again later."
    redirect_to user_path(this_organization)
  end
end
