# typed: true
# frozen_string_literal: true

class Platform::Models::NotificationThread
  # Provide the minimal information for a workflow run inside a notification thread.
  #
  # At this point notification threads with the thread type set to Actions::WorkflowRun
  # are only used for GateRequest events.
  class WorkflowRunMinInfo
    include MinInfoTrait

    sig { returns(Actions::WorkflowRun) }
    attr_reader :workflow_run

    sig { params(workflow_run: Actions::WorkflowRun).void }
    def initialize(workflow_run:)
      @workflow_run = workflow_run
    end

    sig { override.returns(Promise[T.nilable(String)]) }
    def async_title
      workflow_run.async_check_suite.then do |check_suite|
        check_suite&.async_creator.then do |creator|
          "#{creator&.display_login} requested your review to deploy to an environment"
        end
      end
    end

    sig { override.returns(Promise[T.nilable(String)]) }
    def async_url
      workflow_run.async_check_suite.then do |check_suite|
        check_suite&.async_repository.then do
          workflow_run.permalink
        end
      end
    end

    sig { override.returns(Promise[T::Array[User]]) }
    def async_recent_participants
      workflow_run.async_check_suite.then do |check_suite|
        check_suite&.async_creator.then do |creator|
          [creator].compact
        end
      end
    end

    sig { override.returns(Promise[T.nilable(User)]) }
    def async_summary_item_author
      workflow_run.async_check_suite.then do |check_suite|
        check_suite&.async_creator.then do |creator|
          creator
        end
      end
    end

    sig { override.returns(Promise[T.nilable(String)]) }
    def async_summary_item_body
      Promise.new.fulfill("")
    end
  end
end
