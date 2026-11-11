# typed: true
# frozen_string_literal: true

class Platform::Models::NotificationThread
  # Provide the minimal information for a check suite inside a notification thread.
  class CheckSuiteMinInfo
    include MinInfoTrait

    sig { returns(CheckSuite) }
    attr_reader :check_suite

    sig { params(check_suite: CheckSuite).void }
    def initialize(check_suite:)
      @check_suite = check_suite
    end

    sig { override.returns(Promise[T.nilable(String)]) }
    def async_title
      Promise.all([async_run_name, async_attempt]).then do |run_name, attempt|
        status = check_suite.completed? ? StatusCheckConfig.verb_state(check_suite.conclusion) : check_suite.humanized_status
        run_title = "#{run_name} workflow run"
        run_title += ", Attempt ##{attempt}" if attempt.to_i > 1

        "#{run_title} #{status} for #{check_suite.head_branch} branch"
      end
    end

    sig { override.returns(Promise[T.nilable(String)]) }
    def async_check_suite_conclusion
      Promise.new.fulfill(check_suite.conclusion)
    end

    sig { override.returns(Promise[T.nilable(String)]) }
    def async_url
      check_suite.async_repository.then do
        check_suite.async_workflow_run.then do
          check_suite.permalink
        end
      end
    end

    sig { override.returns(Promise[T::Array[User]]) }
    def async_recent_participants
      check_suite.async_creator.then { |user| [user].compact }
    end

    sig { override.returns(Promise[T.nilable(User)]) }
    def async_summary_item_author
      check_suite.async_creator
    end

    sig { override.returns(Promise[T.nilable(String)]) }
    def async_summary_item_body
      Promise.new.fulfill(CheckSuiteEventNotification.new(check_suite).body)
    end

    private

    def async_run_name
      check_suite.async_workflow_run.then do |workflow_run|
        workflow_run&.explicit_name? ? workflow_run.name : check_suite.name
      end
    end

    def async_attempt
      check_suite.async_workflow_run.then do |workflow_run|
        next 1 unless workflow_run

        workflow_run.async_latest_workflow_run_execution.then do |execution|
          next 1 unless execution

          execution.attempt
        end
      end
    end
  end
end
