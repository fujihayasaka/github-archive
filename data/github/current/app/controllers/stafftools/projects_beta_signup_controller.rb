# typed: true
# frozen_string_literal: true

module Stafftools
  class ProjectsBetaSignupController < StafftoolsController
    MEMEX_OPS_CHANNEL = "#memex-ops"
    ISSUES_GRAPH_OPS_CHANNEL = "#issues-graph-ops"

    javascript_bundle :staff
    javascript_bundle :settings

    depends_on_clusters ApplicationRecord::Ballast,
      ApplicationRecord::Billing,
      ApplicationRecord::Collab,
      ApplicationRecord::Configurations,
      ApplicationRecord::Copilot,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Mysql1,
      ApplicationRecord::Mysql2,
      ApplicationRecord::Mysql5,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Repositories,
      only: [:index]

    depends_on_clusters ApplicationRecord::Copilot,
      only: [:index], optional: true

    def index
      @feature = params[:feature]
      beta_signup_query = query.new(
        page: current_page,
        search: params[:query],
      )

      render "stafftools/projects_beta_signup/index",
        locals: {
          beta: beta,
          feature: @feature,
          # Call `memberships` first to ensure the metadata is populated
          memberships: beta_signup_query.memberships,
          metadata: beta_signup_query.member_metadata
        }
    end

    def update
      @feature = params[:feature]

      membership = beta.waitlist.find(params[:membership_id])
      if membership.nil? || membership.member.nil?
        head :not_found
      end
      # Members can be Users or Businessess, but our beta
      # is only enrolling Organizations
      org = membership.member
      if membership.feature_enabled?
        offboard(membership)
        head :ok
      else
        onboard(membership)
        head :ok
      end
    end

    private

    def onboard(membership)
      org = membership.member

      # enable feature flags for organization
      feature_flags.each { |feature_flag| GitHub.flipper[feature_flag].enable(org) }

      # update EarlyAccessMembership record to set feature_enabled: true for organization
      membership.update(feature_enabled: true)

      # Send a slack message to #memex-ops
      send_slack_message(org, true)

      # run onboarding job to send emails to admin
      beta.onboard_job.perform_later(org.login)
    end

    def offboard(membership)
      org = membership.member

      # disable feature flags for organization
      feature_flags.each { |feature_flag| GitHub.flipper[feature_flag].disable(org) }

      # update EarlyAccessMembership record to set feature_enabled: false for organization
      membership.update(feature_enabled: false)

      # Send a slack message to #memex-ops
      send_slack_message(org, false)
    end

    def send_slack_message(org, enabled, chat_client = GitHub::Chatterbox.client)
      message = +":rocket: The `#{@feature}` feature was #{enabled ? "enabled" : "disabled"} for `#{org.login}` by `#{current_user.login}` as part of the #{@feature.capitalize} Beta #{enabled ? "Onboarding" : "Offboarding"} process"
      chat_client.say!(ops_channel, message)
    end

    def beta
      case @feature
      when "tasklists"
        ProjectsTasklistsBeta.new
      else
        head :not_found
      end
    end

    def query
      case @feature
      when "tasklists"
        Stafftools::ProjectsTasklistsBetaSignupQuery
      else
        head :not_found
      end
    end

    def feature_flags
      case @feature
      when "tasklists"
        [:tasklist_block]
      else
        head :not_found
      end
    end

    def ops_channel
      case @feature
      when "tasklists"
        ISSUES_GRAPH_OPS_CHANNEL
      else
        head :not_found
      end
    end
  end
end
