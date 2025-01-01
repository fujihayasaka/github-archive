# typed: true
# frozen_string_literal: true

module PullRequests
  # Handles anything complicated in the merge button area of a pull
  # request.
  class DeploymentsBoxView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    include GateRequestHelper
    include GitHub::Memoizer

    attr_reader :pull
    attr_reader :additional_container_classes

    IN_PROGRESS_STATES  = %w(in_progress queued)
    UNSUCCESSFUL_STATES = %w(failure errored abandoned)
    SUCCESS_STATE       = "active"
    INACTIVE_STATE      = "inactive"
    PENDING_STATE       = "pending"
    WAITING_STATE       = "waiting"

    ALL_STATES = [IN_PROGRESS_STATES, UNSUCCESSFUL_STATES, SUCCESS_STATE, INACTIVE_STATE, PENDING_STATE, WAITING_STATE].flatten

    def can_see_deployments?
      # Don't show the box if you don't have permissions to view deployments
      return false unless pull.repository.writable_by?(current_user)

      # Don't show the box if the repository has never been deployed
      return false if Deployment.where(repository_id: pull.repository.id).empty?

      # Don't show the box if the PR is closed/merged and there were no deploys
      return false if !pull.open? && deploys_for_current_head.empty?

      true
    end

    def container_classes
      "branch-action #{additional_container_classes}"
    end

    def css_class_for_deployment_summary_status
      case deployment_summary_status
      when :success
        "color-fg-success"
      when :in_progress, :waiting
        "color-fg-attention"
      when :unsuccessful
        "color-fg-danger"
      when :not_deployed
        "color-fg-muted"
      end
    end

    def deploy_box_header_for_deployment_summary_status(gate_requests)
      case deployment_summary_status
      when :success
        "This branch was successfully deployed"
      when :waiting
        if is_pending_approval(gate_requests)
          "This branch is waiting for a deployment approval"
        else
          "This branch is waiting to be deployed"
        end
      when :pending
        "This branch is pending to be deployed"
      when :in_progress
        "This branch is being deployed"
      when :unsuccessful
        "This branch had an error being deployed"
      when :not_deployed
        "This branch has not been deployed"
      when :previously_deployed
        "This branch was previously deployed"
      end
    end

    # Returns a "summary" of the current PR deployment status
    # Can be one of:
    # :success      - The head oid has successful deploys, no pending/queued deploys, no errored deploys that have not been superseded.
    # :in_progress  - There is at least one queued or in_progress deploy, and no errored deploys that have not been superseded.
    # :unsuccessful - There is an errored deployment on at least one environment for this head oid, and there are no later deploys
    #                with the same oid and environment that are in_progress, queued, or successful.
    # :not_deployed - The PR was never deployed.
    # :previously_deployed - All deploys are 'inactive'.
    def deployment_summary_status
      @deployment_summary_status ||= if all_deploys.empty?
        # There are 0 deploys
        :not_deployed
      elsif latest_deploy_per_environment.all? { |deploy| deploy.state == INACTIVE_STATE }
        # All deploys are inactive
        :previously_deployed
      elsif latest_deploy_per_environment.any? { |deploy| deploy.state == PENDING_STATE }
        # Some deploys are pending
        :pending
      elsif latest_deploy_per_environment.any? { |deploy| deploy.state == WAITING_STATE }
        # Some deploys are waiting
        :waiting
      elsif latest_deploy_per_environment.any? { |deploy| UNSUCCESSFUL_STATES.include?(deploy.state) }
        # There is at least one unsuccessful deploy
        :unsuccessful
      elsif latest_deploy_per_environment.any? { |deploy| IN_PROGRESS_STATES.include?(deploy.state) }
        # There is at least one in_progess deploy
        :in_progress
      else
        # All deploys succeeded
        :success
      end
    end

    # A string that summarizes deployments by environment, used in the view
    # E.g. "8 successful, 1 in progress, and 2 failed deployments"
    def deployment_environment_summary_info
      deploys_by_state = latest_deploy_per_environment.group_by(&:state)

      summary_info = []

      ALL_STATES.each do |state|
        next unless (state_deploys = deploys_by_state[state])

        deploy_count = state_deploys.count
        outdated_count = state_deploys.count { |deploy| deploy.sha != pull.head_sha }

        label = state == "failure" ? "failed" : state.humanize(capitalize: false)

        if outdated_count == deploy_count
          label += " (outdated)"
        elsif outdated_count > 0
          label += " (#{outdated_count} outdated)"
        end

        summary_info << ["#{deploy_count} #{label}", deploy_count]
      end

      summary_info.compact
    end

    # Returns an array of the most recent deploys for each deployed environment
    # This list of deploys provides a "current state" of each environment.
    def latest_deploy_per_environment
      @latest_deploy_per_environment ||= all_deploys.group_by(&:environment).map do |_environment, deploys|
        deploys.sort_by { T.must(_1.id) }.last
      end
    end

    def text_color_for_deployment(deployment)
      case deployment.state
      when "active"
        "color-fg-success"
      when "in_progress", "queued", "pending"
        "color-fg-attention"
      when "failure", "errored"
        "color-fg-danger"
      when "inactive", "abandoned"
        "color-fg-muted"
      end
    end

    def reason_data_for_deployment(deployment)
      check_run = deployment&.check_run
      workflow_run = check_run&.check_suite&.workflow_run

      return unless check_run && workflow_run

      {
          text: workflow_name(check_run.display_name, workflow_run.run_number),
          link: workflow_run.permalink
      }
    end

    # Returns an array of all deployments of this PR that are not outdated
    def deploys_for_current_head
      @deploys_for_current_head ||= if GitHub.flipper.enabled?(:deployments_for_current_head_simpler_query)
        Deployment.includes(check_run: [:check_suite]).where(repository_id: pull.repository_id, sha: pull.head_sha)
      else
        all_deploys.select { |deploy| deploy.sha == pull.head_sha }
      end
    end

    # Returns an array of all deployments made to this PR
    sig { returns(T::Array[Deployment]) }
    memoize def all_deploys
      Deployment.for_pull_request(pull)
        .includes(check_run: [:check_suite])
        .to_a
    end
  end
end
