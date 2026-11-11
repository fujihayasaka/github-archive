# typed: true
# frozen_string_literal: true

# These are GlobalInstrumenter subscriptions that emit Hydro events related to GitHub SweAgent v0.
Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("copilot.v0.SweAgentFeedback") do |payload|
    message = {
      request_id: payload[:request_id],
      context: {
        organization_id: payload[:organization_id],
        repository_id: payload[:repository_id],
        pull_request_id: payload[:pull_request_id],
        feedback_target_id: payload[:feedback_target_id],
        feedback_target: payload[:feedback_target],
        user_analytics_tracking_id: payload[:analytics_tracking_id],
      },
      type: payload[:type],
    }

    publish(message, schema: "copilot.swe_agent.v0.Feedback")
  end

  subscribe("copilot.v0.SweAgentRestrictedFeedback") do |payload|
    message = {
      request_id: payload[:request_id],
      context: {
        organization_id: payload[:organization_id],
        repository_id: payload[:repository_id],
        pull_request_id: payload[:pull_request_id],
        feedback_target_id: payload[:feedback_target_id],
        feedback_target: payload[:feedback_target],
        user_analytics_tracking_id: payload[:analytics_tracking_id],
      },
      text_response: payload[:text_response],
      feedback_choice: payload[:feedback_choice],
    }

    publish(message, schema: "copilot.swe_agent.v0.RestrictedFeedback")
  end

  subscribe("copilot.swe_agent.experiment.job_created") do |payload|
    message = {
      request_id: payload[:request_id],
      context: {
        actor_id: payload[:actor].id,
        repository_id: payload[:repository].id,
        repository_owner_id: payload[:repository_owner].id,
        issue_id: payload[:issue].id,
        user_analytics_tracking_id: payload[:actor].analytics_tracking_id,
      },
      similar_issue_ids: payload[:similar_issue_ids],
      closing_pr_ids: payload[:closing_pr_ids],
      creation_id: payload[:creation_id],
      job_id: payload[:job_id],
    }

    publish(message, schema: "copilot.swe_agent.v0.ExperimentJobCreated")
  end
end
