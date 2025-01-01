# typed: true
# frozen_string_literal: true

# Orchestrates the pre-destroy callback behavior when deleting a project from
# the database. This controls the order of the destroy steps as well as error
# handling. Wrapping them up in one place lets us better control
# failure conditions. This object must be used as shared instance across the
# callback chain
#
# Warning:
# All destroy callbacks (except after_commit) will be run inside a transaction.
# Long running transactions should be avoided at all costs
#
# Examples
#
#   # rails callbacks involved in destroying projects should use an instance variable

# Always reuse the same destroy project callback because we have state that
# is shared across the callback chain. This is bad, but can't be avoided without
# serious refactoring.
#
#   before_destroy :destroy_project_callbacks_before_destroy
#   after_commit   :destroy_project_callbacks_after_commit, :on => :destroy
#
#   def destroy_project_callbacks
#     @destroy_callback ||= DestroyProjectCallbacks.new
#   end
#
#   def destroy_project_callbacks_before_destroy
#     destroy_project_callbacks.before_destroy(self)
#   end
#
#   def destroy_project_callbacks_after_commit
#     destroy_project_callbacks.after_commit(self)
#   end
#
# This is inspired by DestroyUserCallbacks
#
class DestroyProjectCallbacks

  # Run the pre-destroy cleanup steps for the project. Because this is registered
  # as a before_destroy callback, if it returns false or throws an exception,
  # the project record will not be destroyed.
  #
  # project - The Project that's about to be deleted from the database.
  #
  # Returns false to stop the destroy callback chain.
  def before_destroy(project)
    prepare_project_events(project)
  end

  def prepare_project_events(project)
    return if Rails.env.test? && !Hook.delivers_in_test?

    actor_id = GitHub.context[:actor_id] || User.ghost.id
    project.cards.each do |project_card|
      project.construct_future_event do
        Hook::Event::ProjectCardEvent.new(
          action: :deleted,
          project_card_id: project_card.id,
          actor_id: actor_id,
          triggered_at: Time.now,
        )
      end
    end
    project.columns.each do |project_column|
      project.construct_future_event do
        Hook::Event::ProjectColumnEvent.new(
          action: :deleted,
          project_column_id: project_column.id,
          actor_id: actor_id,
          triggered_at: Time.now,
        )
      end
    end
    project.construct_future_event do
      Hook::Event::ProjectEvent.new(
        action: :deleted,
        project_id: project.id,
        actor_id: actor_id,
        triggered_at: Time.now,
      )
    end
  end

  def after_commit(project)
    project.enqueue_delete
  end
end
