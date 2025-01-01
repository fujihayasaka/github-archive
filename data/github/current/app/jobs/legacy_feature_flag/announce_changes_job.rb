# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

module LegacyFeatureFlag
  class AnnounceChangesJob < ApplicationJob
    queue_as :low # rubocop:todo GitHub/DoNotUseGenericBackgroundJobQueues

    def self.enabled?
      !GitHub.enterprise?
    end

    def perform(announcement_issue, feature_flag)
      from_user = announcement_issue.user
      title = announcement_issue.title
      body = announcement_issue.body

      #####
      # Notify any repos
      #####

      success_repos = []
      failed_repos = []
      feature_flag.private_github_repos.each do |repo|
        with_write do
          issue = Issue.create!(
            repository: repo,
            user: from_user,
            title: title,
            body: body
          )
          issue.notify_socket_subscribers
          success_repos << issue.permalink
        end
      rescue ActiveRecord::RecordInvalid
        failed_repos << repo.name_with_display_owner
      end

      notify_progress(announcement_issue, "Repositories", success_repos, failed_repos)

      #####
      # Notify any users
      #####

      success_users = []
      failed_users = []
      feature_flag.github_employees.each do |employee|
        GitHub::Chatterbox.client.say!("@#{employee.display_login}", <<~EOF)
        From: <@#{from_user.display_login}>:

        # #{title}

        #{body}
        EOF
        success_users << "[#{employee.display_login}](#{UrlHelpers.user_path(employee, host: GitHub.host_name)})"
      rescue Chatterbox::Error
        failed_users << "[#{employee.display_login}](#{UrlHelpers.user_path(employee, host: GitHub.host_name)})"
      end

      notify_progress(announcement_issue, "Hubbers", success_users, failed_users)

      #####
      # Notify any teams
      #####
      success_teams = []
      failed_teams = []
      feature_flag.github_teams.each do |team|
        with_write do
          post = team.discussion_posts.create!(
            title: title,
            body: body,
            private: false,
            user: from_user
          )
          url = UrlHelpers.team_discussion_url(org: "github", team_slug: team.slug, number: post.number, host: GitHub.host_name)
          success_teams << "[#{team.name}](#{url})"
        end
      rescue ActiveRecord::RecordInvalid
        failed_teams << "[#{team.name}](#{UrlHelpers.team_url(org: "github", team_slug: team.slug, host: GitHub.host_name)})"
      end

      notify_progress(announcement_issue, "Teams", success_teams, failed_teams)

      #####
      # Craft and send the final message
      #####

      success = []
      success << "#{success_repos.count} #{"repository".pluralize(success_repos.count)}" if feature_flag.private_github_repos.present?
      success << "#{success_teams.count} #{"team".pluralize(success_teams.count)}" if feature_flag.github_teams.present?
      success << "#{success_users.count} #{"Hubber".pluralize(success_users.count)}" if feature_flag.github_employees.present?

      failed = []
      failed << "failed for GitHub #{'Repository'.pluralize(failed_repos.size)} #{failed_repos.to_sentence}" if feature_flag.private_github_repos.present? && failed_repos.present?
      failed << "failed for GitHub #{'Team'.pluralize(failed_teams.size)} #{failed_teams.to_sentence}" if feature_flag.github_teams.present? && failed_teams.present?
      failed << "failed for #{'Hubber'.pluralize(failed_users.size)} #{failed_users.to_sentence}" if feature_flag.github_employees.present? && failed_users.present?

      msg = "Successfully made issues for #{success.empty? ? "no one" : success.to_sentence}"
      msg += ", however #{failed.to_sentence}" unless failed.empty?

      with_write do
        announcement_issue.create_comment(from_user, "**Finished!**\n\n#{msg}")
        announcement_issue.close(from_user)
      end
    end

    def notify_progress(announcement_issue, model, success, failed)
      body = <<~EOF
      ### Results for #{model}

      **Success:**
      #{success.present? ? success.map { |f| "- #{f}" }.join("\n") : "None"}

      **Failed:**
      #{failed.present? ? failed.map { |f| "- #{f}" }.join("\n") : "None"}
      EOF
      with_write do
        announcement_issue.create_comment(announcement_issue.user, body)
      end
    end
  end
end
