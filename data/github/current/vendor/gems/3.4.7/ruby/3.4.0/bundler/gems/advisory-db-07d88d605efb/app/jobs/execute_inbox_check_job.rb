# frozen_string_literal: true

class ExecuteInboxCheckJob < ApplicationJob
  queue_as :high

  # This job is a generic job that executes a "check" as defined in another Check class
  def perform(check_class_name:, review:)
    check_class = check_class_name.constantize
    ::GitHub::Telemetry::Logs.logger.debug { "Executing check run #{check_class} for #{review.class}:#{review.ghsa_id}" }
    CheckSuiteRunner.update_check_status(check_class: check_class, review: review, status: "running")

    check_result =
      begin
        check_class.execute_check(review: review)
      rescue StandardError => error
        GitHub::Telemetry::Logs.logger.error("Exception raised while running inbox validation checks",
          {
            exception: error,
            "gh.ghsa_id": review.ghsa_id,
          })

        CheckResult.new(
          status: "failed",
          title: "Check Raised Exception",
          summary: error.message,
        )
      end

    CheckSuiteRunner.update_check_status(
      check_class: check_class,
      review: review,
      status: check_result.status,
      message: [check_result.title, check_result.summary].compact_blank.join(" - "),
    )
  end
end
