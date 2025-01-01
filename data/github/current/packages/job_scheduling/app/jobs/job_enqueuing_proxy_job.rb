# typed: true
# frozen_string_literal: true

class JobEnqueuingProxyJob < ApplicationJob
  queue_as :job_enqueueing_by_proxy

  sig { params(job_class: String).void }
  def perform(job_class)
    job_class.safe_constantize.perform_later
  rescue NoMethodError => e
    e.message << " while trying to perform #{job_class}"
    Failbot.report(e)
  end
end
