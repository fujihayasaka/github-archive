# typed: true
# frozen_string_literal: true

# A controller that reports job status to `fetchPoll` pollers. This prevents the
# need for a different polling endpoint for each of our various jobs.
#
# Examples
#
# In the controller:
#
#   # Save job status to memcache.
#   status = JobStatus.new
#   status.save
#
#   # Start a job, pass it the job status id.
#   IssueTriageJob.perform_later(status.id, issues.map(&:id), current_user.id, params)
#
#   # Return the job url to poller.
#   respond_to do |format|
#    format.json { render json: {job: {url: job_status_url(status.id)} }
#   end
#
# In the job class:
#
#   def self.perform(job_id, issue_ids, current_user_id, params)
#     # Find the status created in the controller.
#     status = JobStatus.find(job_id)
#     return unless status
#
#     # Update memcache with success or error state.
#     status.track do
#       # do some work
#     end
#   end
#
# In the client:
#
#   # Poll the job url returned by the controller.
#   fetchPoll('/_jobs/1234...')
#
class JobsController < ApplicationController

  # We can safely skip the `perform_conditional_access_checks` filter
  # as background jobs (not actions) are not customer-owned resources.
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  before_action :login_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::SecurityOverviewAnalytics,
    ApplicationRecord::Repositories,
    ApplicationRecord::IssuesPullRequests,
    only: [:show]

  def show
    job = find_job(params[:id])
    return head 404 unless job

    status =
      if !job.finished?
        202
      elsif job.success?
        200
      else
        500
      end

    render status: status, json: { job: job.as_json }
  end

  private

  def find_job(id)
    default = -> { JobStatus }
    status_classes = JobStatus.descendants
    status_class = status_classes.find(default) do |klass|
      next unless klass.methods.include? :handles_id?
      klass.handles_id?(id)
    end

    status_class.find(id, meta: { current_user: current_user })
  end
end
