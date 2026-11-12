# frozen_string_literal: true

# Goes slowly to allow testing retry_on_dirty_exit behavior
class SlowJob < ApplicationJob
  queue_as :default
  retry_on_dirty_exit

  def perform(seconds_to_sleep: 600)
    Dependabot::Logger.info(
      msg: "Sleeping for #{seconds_to_sleep} seconds",
      executions: executions
    )
    sleep(seconds_to_sleep)
  end
end
