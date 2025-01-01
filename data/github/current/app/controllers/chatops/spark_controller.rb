# typed: true
# frozen_string_literal: true

require "chatops-controller"

class Chatops::SparkController < ApplicationController
  include ::Chatops::Controller

  # Chatops boilerplate
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  # Chatops boilerplate
  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:list]

  # Chatops boilerplate
  private def verify_authenticity_token?
    false # robots do this
  end

  chatops_namespace :spark
  chatops_help "Commands for getting information about sparks"
  chatops_error_response "More information is available [in Sentry](https://sentry.io/organizations/github/issues/). Try re-running the command or ask for help in [#spark](https://github-grid.enterprise.slack.com/archives/C08F7R0RW4T)."

  # Not currently restricted.
  #ALLOWED_TEAMS = ["pizza_teams/spark-workbench"].freeze

  # Example spark URL: `https://github.com/spark/justinmcbride/hello-world-app`
  GITHUB_COM_REGEX = %r{
    \A
    (?:https://github.com/spark/)? # Optional beginning of URL
    (?<owner>[a-z0-9\-\_]+)        # Owner
    /                              # Separator
    (?<spark>[a-z0-9\-]+)          # Spark name
    .*
    \z
  }ix

  # Example spark URL: `https://morse-2--justinmcbride.github.app`
  GITHUB_APP_REGEX = %r{
    \A
    (?:https:\/\/)?         # Optional beginning of URL
    ([a-z0-9\-]+--)?        # revision
    (?<spark>[a-z0-9\-]+)   # Spark name
    --                      # Separator
    (?<owner>[a-z0-9\-]+)   # Owner
    \.github\.app
    .*
    \z
  }ix

  # Example user profile URL: `https://github.com/justinmcbride`
  GITHUB_USER_PROFILE = %r{
    \A
    (?:https:\/\/)?           # Optional beginning of URL
    (?:www\.)?                # Optional www subdomain
    github\.com\/             # GitHub domain
  (?<user>[a-z0-9\-\_]+)    # User's GitHub username
  \/?                        # Optional trailing slash
    \z
  }ix

  chatop :info,
    /info\s+(?<id>.*)?/,
    "info <url|workbench-uuid|runtime-app-permanent-name> - Return information on a Spark" do
      # Grab the url from the params
      id = jsonrpc_params.require(:id)

      owner, workbench, runtime_app = self.class.find_spark_by_url(id) ||
        self.class.find_spark_by_workbench_uuid(id) ||
        self.class.find_spark_by_runtime_app(id)

      unless workbench || runtime_app
        chatop_send ":not_found: Spark not found", options: { thread_style: 1, color: "#901a17" }
        return
      end

      # Let's create hashes which will store the info we want to return
      workbench_info = {
        "UUID" => workbench&.uuid_string,
        "Name" => workbench&.name,
        "Description" => workbench&.description,
        "Created on" => workbench&.created_at&.strftime("%Y-%m-%d %H:%M:%S UTC"),
        "Updated on" => workbench&.updated_at&.strftime("%Y-%m-%d %H:%M:%S UTC"),
      }

      runtime_info = {
        "Permanent name" => runtime_app&.permanent_name,
        "Friendly name" => runtime_app&.friendly_name,
        "Visibility" => runtime_app&.visibility,
      }
      runtime_info.merge!({
        "Visible to org" => "[#{runtime_app&.visibility_organization.display_login}](#{runtime_app&.visibility_organization.permalink})"
      }) if runtime_app&.visibility == "selected_orgs"

      last_deploy = runtime_app&.runtime_app_deploys&.where&.not(display_name: "spark-preview")&.last
      if last_deploy
        # https://${friendlyName}--${deployLogin}.${domainBase}
        deployed_url = "https://#{runtime_app&.friendly_name}--#{runtime_app&.runtime_app_owner&.deploy_login}.#{runtime_app&.runtime_app_owner&.deployment_domain_base}"
        runtime_info.merge!({
          "Published URL" => "[#{deployed_url}](#{deployed_url})"
        })
      else
        runtime_info.merge!({
          "Published URL" => nil
        })
      end

      owner_info = {
        "Owner" => "[#{owner&.display_login}](#{owner&.permalink})",
        "Permanent name" => runtime_app&.runtime_app_owner&.permanent_name,
        "Deployment domain" => runtime_app&.runtime_app_owner&.deployment_domain_base,
      }

      # Format the data for display with section headers
      output_lines = []

      # Workbench section
      output_lines << ":spark: *Workbench Information*"
      workbench_info.each do |key, value|
        output_lines << "  • #{key}: #{value || 'N/A'}"
      end

      # Runtime section
      output_lines << "\n*⚡ Runtime Information:*"
      runtime_info.each do |key, value|
        output_lines << "  • #{key}: #{value || 'N/A'}"
      end

      # Owner section
      output_lines << "\n*👤 Owner Information:*"
      owner_info.each do |key, value|
        output_lines << "  • #{key}: #{value || 'N/A'}"
      end

      # Return the formatted output
      chatop_send output_lines.join("\n"), options: { thread_style: 1, color: "#49be25" }
    end

  chatop :evergreen,
    /evergreen\s+(?<id>.*)?/,
    "evergreen <url|handle|email> - Return eligibility of a user for Spark evergreen access" do
    # Parse out the id param, which will either be a GitHub handle (User.display_login) or a link to the user's profile
    id = jsonrpc_params.require(:id)

    users = [self.class.find_user_by_url(id), User.find_by_login(id)]
    users.concat(User.all_with_profile_email(id))
    users.compact!

    if users.empty?
      chatop_send ":not_found: User not found", options: { thread_style: 1, color: "#901a17" }
      return
    end

    # Aggregate all responses and send a single message to simplify testing/consumption
    messages = users.map do |user|
      is_user_emu = user.is_emu_and_not_first_owner?
      message_emu = is_user_emu ? "❌ EMU user: Yes" : "✅ EMU user: No"
      copilot_user = Copilot::User.new(user)
      copilot_auth = Copilot::Authorizer.new(copilot_user)
      message_copilot = copilot_auth.has_paid_access? ? "✅ Copilot access: #{copilot_auth.verbose_reason}" : "❌ Copilot access: #{copilot_auth.verbose_reason}"

      should_grant = !is_user_emu && copilot_auth.has_paid_access?
      message_grant = should_grant ? ":spark: ✅ Grant access: Yes :spark: :spark:" : "🚫 Grant access: No 🚫"

      <<~MESSAGE
        User: [#{user.display_login}](#{user.permalink})
        #{message_emu}
        #{message_copilot}
        #{message_grant}
      MESSAGE
    end

    separator = "\n---\n"
    chatop_send messages.join(separator), options: { thread_style: 1, color: "#49be25" }
  end

  def self.find_user_by_url(maybe_url)
    return unless maybe_url.present?

    match = GITHUB_USER_PROFILE.match(maybe_url.strip)
    return unless match

    user_name = match[:user]
    return unless user_name

    User.find_by_login(user_name)
  end

  # Extract owner and spark name from a spark URL or path
  # @param url [String] The spark URL or path to parse
  # @return [Hash, nil] A hash with :owner and :spark keys, or nil if invalid
  def self.extract_spark_info(url)
    return nil if url.nil? || url.empty?

    match = GITHUB_COM_REGEX.match(url.strip) || GITHUB_APP_REGEX.match(url.strip)
    return nil unless match

    {
      owner: match[:owner],
      spark: match[:spark]
    }
  end

  def self.find_spark_by_url(maybe_url)
    spark_info = self.extract_spark_info(maybe_url)
    return unless spark_info

    # Destructure and validate the spark_info hash
    owner_name, spark_name = spark_info.values_at(:owner, :spark)
    return unless owner_name && spark_name

    user = User.find_by_login(owner_name)
    return unless user

    workbench = Spark::Workbench.by_friendly_name_or_uuid(
      user.id,
      spark_name
    )

    [user, workbench, workbench&.runtime_app]
  end

  def self.find_spark_by_workbench_uuid(maybe_uuid)
    return if maybe_uuid.nil? || maybe_uuid.empty?

    uuid = Spark::Workbench.binary_uuid(maybe_uuid)
    workbench = Spark::Workbench.find_by(uuid:)

    return unless workbench

    [workbench.user, workbench, workbench.runtime_app]
  end

  def self.find_spark_by_runtime_app(maybe_permanent_name)
    return if maybe_permanent_name.nil? || maybe_permanent_name.empty?

    runtime_app = Spark::RuntimeApp.find_by(permanent_name: maybe_permanent_name)

    return unless runtime_app

    workbench = Spark::Workbench.find_by(runtime_app:)

    [runtime_app.user, workbench, runtime_app]
  end
end
