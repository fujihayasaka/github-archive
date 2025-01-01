# typed: strict
# frozen_string_literal: true

class OrganizationOnboarding::TasksController < OrganizationOnboarding::ApplicationController
  extend T::Sig

  before_action :non_emu_required

  ALLOW_MAP = T.let(
    {
      learn_dependency_review: OnboardingTasks::AdvancedSecurity::LearnDependencyReview,
      security_overview: OnboardingTasks::AdvancedSecurity::SecurityOverview,
      customize_permission: OnboardingTasks::Organizations::CustomizePermission
    },
    T::Hash[Symbol, T.class_of(OnboardingTasks::AbstractTask)]
  )

  sig { void }
  def update
    task = task_symbol
    result = complete_task

    respond_to do |format|
      format.json do
        case result
        when :unknown_task
          return render json: {
            error: "Invalid task: #{task}"
          }, status: :unprocessable_entity
        when :success
          return render json: {
            task_completed: true,
          }
        else
          render json: {
            error: "Failed to complete task: #{task}"
          }, status: 500
        end
      end
      format.html do
        case result
        when :unknown_task
          flash[:error] = "Unknown task"
          safe_redirect_to params[:return_to]
        when :success
          flash[:success] = "Completed task"
          safe_redirect_to params[:return_to]
        else
          flash[:error] = "Failed to complete task"
          safe_redirect_to params[:return_to]
        end
      end
    end
  end

  private

  sig { returns Symbol }
  def task_symbol
    task = params[:task]
    return :unknown_task unless task
    task.to_sym
  end

  sig { returns Symbol }
  def complete_task
    task = task_symbol
    unless ALLOW_MAP.key?(task)
      return :unknown_task
    end
    result = T.must(ALLOW_MAP[task]).new(taskable: this_organization, user: current_user).complete
    result ? :success : :failure
  end
end
