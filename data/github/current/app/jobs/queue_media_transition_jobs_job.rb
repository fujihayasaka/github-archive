# typed: true
# frozen_string_literal: true

class QueueMediaTransitionJobsJob < ApplicationJob
  SCHEDULE_INTERVAL = 10.minutes

  queue_as :lfs
  schedule interval: SCHEDULE_INTERVAL
  retry_on_dirty_exit
  exempt_from_tenant_context_requirement

  def perform
    GitHub.dogstats.gauge("lfs.transitions", Media::Transition.count)
    @count = 0
    each_transition &:async_perform
    GitHub.dogstats.gauge("lfs.transitions.enqueued", @count)
  end

  def each_transition(&block)
    Media::Transition.operations.each_value do |op|
      each_operation_transition(op, &block)
    end
  end

  def each_operation_transition(operation)
    last_id = T.let(0, T.nilable(Integer))

    loop do
      Media::Transition.throttle do
        transitions = Media::Transition.where("operation = ? AND id > ?", operation, last_id).order("id ASC").limit(500)

        return if transitions.blank?

        requeuable = transitions.reject(&:earlier_transition?)
        requeuable.sort_by!(&:id)
        requeuable.each { |t| yield t }
        last_id = transitions.map(&:id).max
        @count += requeuable.length
      end
    end
  end
end
