# typed: true
# frozen_string_literal: true

# This class is used to render a task component for a given task.
# It inherits from OnboardingTasks::TaskComponent, which is a component that is
# used to render a generic task.
# We change the default behavior of the task component to render a task wrapped
# by a button that when clicked, will do a form submission to create a demo repo
# before redirecting to the task itself.

# See app/components/onboarding_tasks/task_component.rb for more information about
# the OnboardingTasks::TaskComponent
class Onboarding::Organizations::TaskComponent < OnboardingTasks::TaskComponent
  def content_wrapper(&block)
    if task.require_demo_repository? && !task.demo_repo
      button_to(organization_onboarding_demo_repositories_path(task.taskable, task: task.class.task_key), method: :post, data: { **link_data_attributes, disable_with: "Creating..." }, class: class_names(task_link_classes, "text-left"), form: { class: "height-full" }) do
        yield
      end
    else
      super
    end
  end
end
