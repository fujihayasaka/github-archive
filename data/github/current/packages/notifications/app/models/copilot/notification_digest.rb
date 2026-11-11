# typed: true
# frozen_string_literal: true

module Copilot
  class NotificationDigest
    # Result wrapper for API responses that can contain either success data or an error
    class Result
      attr_reader :data, :digest_summary, :error, :error_message

      def initialize(data: nil, digest_summary: nil, error: nil, error_message: nil, event: nil, model: nil, user: nil)
        @data = data
        @digest_summary = digest_summary
        @error = error
        @error_message = error_message

        report_error
        instrument_error_telemetry(event, model, user)
      end

      def success?
        @error_message.nil?
      end

      def failure?
        !success?
      end

      private

      def report_error
        Failbot.report(error) if error
      end

      def instrument_error_telemetry(event, model, user)
        return unless event && user && failure?

        GlobalInstrumenter.instrument("copilot_notifications_inbox.telemetry", {
          user: user,
          event: event,
          metadata: {
            "digest_version" => PROMPT_VERSION,
            "error_message" => error_message,
            "full_error_message" => error&.message.to_s,
            "error_type" => error&.class&.name.to_s,
            "model" => model,
          },
        })
      end
    end

    attr_reader :user, :copilot_notifications, :model

    PROMPT_VERSION = "2"
    CHARS_PER_TOKEN = 4

    def initialize(user:, notifications:)
      @user = user
      @copilot_notifications = create_copilot_notifications(notifications)
      @model = if FeatureFlag.vexi.enabled?(:notifications_copilot_digest_five, user, default: false)
        "gpt-5"
      elsif FeatureFlag.vexi.enabled?(:notifications_copilot_digest_five_mini, user, default: false)
        "gpt-5-mini"
      else
        "gpt-4o-mini"
      end
    end

    # Build notification summaries from Copilot::Notification objects.
    # Public so the controller can pass it to CopilotDigestJob for the agent path.
    # @return [Array<Hash>] Array of notification summary hashes
    def notification_summaries
      copilot_notifications.map do |copilot_notification|
        notification = copilot_notification.notification
        summary = {
          id: notification.global_relay_id,
          title: notification.title,
          reason: notification.reason,
          thread_type: notification.thread_type,
          updated_at: notification.last_updated_at&.iso8601,
          unread: notification.unread?,
          subject: copilot_notification.subject_data
        }

        if notification.list.is_a?(Repository)
          summary[:repository] = {
            owner: notification.list.owner_display_login,
            name: notification.list.name
          }
        end

        summary.compact
      end
    end

    # Build the digest prompt from the current notifications.
    # Public so the controller can pass it to CopilotDigestJob.
    def build_digest_prompt
      <<~PROMPT
        You are a helpful assistant analyzing GitHub notifications. Analyze all the notifications below and:
        1. Group each notification into a meaningful category based on its current state and what action is needed (e.g., "Ready for next steps", "Waiting on others", "Needs your review", "Requires discussion", "Security concerns", "CI/CD failures", etc.)
        2. Assign a priority score from 0-10 (10 being highest priority) based on urgency and importance
        3. Provide a brief recommended next step for each notification
        4. Suggest 1-2 call-to-action buttons

        Each notification includes:
        - Basic info: title, reason (why the user received it), thread_type, repository, updated_at, unread status
        - Subject details: type-specific metadata about the Issue, PullRequest, Discussion, Release, etc.

        Use the subject information to categorize and prioritize. For example:
        - PRs where the user is requested as part of a team reviewer -> high priority, category about needing team review
        - PRs where the user is requested as a direct reviewer (is_direct_reviewer = true) -> high priority, category about the pull request needing their specific review
        - PRs waiting for CI or other reviewers -> category about waiting
        - Issues/PRs with recent comments needing response -> category about discussion
        - Approved PRs ready to merge -> high priority, category about next steps
        - Failed workflow runs -> high priority, category about CI/CD
        - Security advisories -> priority based on severity, category about security

        Example category names (use these or similar concise names):
        - "Needs your review"
        - "Ready for next steps"
        - "Waiting on others"
        - "Active conversations"
        - "CI/CD failures"
        - "Security concerns"

        Keep category names concise (2-4 words) and consistent across similar notifications.
        If no appropriate category can be determined for a notification, place it in the "Other" category.

        Notifications:
        #{notification_summaries.to_json}

        Respond with a JSON hash
        - A field "digest_summary" with a brief 1-2 sentence summary of the overall state of the user's notifications and categories.
        - An array for the field "items" where each element has:
          - "id": the notification id (must match the id from the input)
          - "category": a concise category name (2-4 words)
          - "priority": a number from 0-10
          - "recommendation": a brief recommendation string (3-10 words) for the next step the user should take. Examples: "Review documentation pull request", Review pull request to update Readme.md", "Reply to new comment", "Merge approved Pull Request", "Check CI failure details", "Review security advisory"
          - "summary": a brief 1-2 sentence summary of the notification content and state of the subject (e.g., "Your PR is waiting on review from @alice and has a failing check", "An issue you are subscribed to has new comments", "A new security advisory has been published for a repository you contribute to", "Your review is specifically requested")
          - "ctas": an array of 1-2 action button labels selected ONLY from this list: #{Copilot::Notification::CTAS.to_json}. If none are appropriate, return an empty array.

        Example response structure:
        {
          "digest_summary": "",
          "items": [
            {
              "id": "",
              "category": "",
              "priority": 0,
              "recommendation": "",
              "summary": "",
              "ctas": [""]
            }
          ]
        }

        Only respond with valid JSON, no other text.
      PROMPT
    end

    def generate_digest(response)
      generated_text = response_content(response)

      if generated_text.present?
        json_text = extract_json(generated_text)
        parsed_response = JSON.parse(json_text)

        return Result.new(error_message: "Unexpected digest response format", event: "digest_error.generating_failed.parsing_failed", model: model, user: user) unless parsed_response.is_a?(Hash)

        digest_summary = parsed_response["digest_summary"]
        items = parsed_response["items"]

        return Result.new(error_message: "Unexpected digest response format", event: "digest_error.generating_failed.parsing_items_failed", model: model, user: user) unless items.is_a?(Array)

        # Build a lookup map by notification id for efficient matching
        notifications_by_id = copilot_notifications.index_by { |cn| cn.notification.global_relay_id }

        # Group notifications by category
        categorized = Hash.new { |h, k| h[k] = [] }

        items.each do |item|
          next unless item.is_a?(Hash)

          id = item["id"]
          next if id.nil?

          copilot_notification = notifications_by_id[id]
          next if copilot_notification.nil?

          category = item["category"] || "Other"
          categorized[category] << copilot_notification

          copilot_notification.recommendation = item["recommendation"].to_s
          copilot_notification.summary = item["summary"].to_s
          copilot_notification.ctas = Array(item["ctas"])
          copilot_notification.priority = item["priority"].to_i
          copilot_notification.metadata[:model] = model
          copilot_notification.metadata[:version] = PROMPT_VERSION

          instrument_telemetry("digest_item_generated", {
            "category" => category,
            "ctas" => item["ctas"],
            "priority" => item["priority"],
            "model" => model,
            "version" => PROMPT_VERSION,
            "recommendation" => item["recommendation"],
            "summary" => item["summary"],
            "subject_type" => copilot_notification.subject_data[:type].to_s,
          })
        end

        # Sort each category by priority (highest first)
        categorized.each do |category, notifs|
          categorized[category] = notifs.sort_by { |n| -n.priority }
        end

        # Ensure "Other" is the last category if it exists so we render it last
        if categorized.key?("Other")
          other_notifications = categorized.delete("Other")
          categorized["Other"] = other_notifications
        end

        Result.new(data: categorized, digest_summary: digest_summary)
      else
        Result.new(error_message: "Copilot did not return any digest items", event: "digest_error.generating_failed", model: model, user: user)
      end
    rescue JSON::ParserError => e
      Result.new(error_message: "Unable to process digest. Please try again later.", error: e, event: "digest_error.generating_failed.parsing_failed", model: model, user: user)
    end

    private

    def instrument_telemetry(event, metadata)
      GlobalInstrumenter.instrument("copilot_notifications_inbox.telemetry", {
        user: user,
        event: event,
        metadata: metadata,
      })
    end

    def estimate_tokens(text)
      (text.length / CHARS_PER_TOKEN).to_s
    end

    def response_content(response)
      response.dig("choices", 0, "message", "content") || response.dig(:choices, 0, :message, :content)
    end

    # Wraps raw notifications in Copilot::Notification objects and builds subject data
    # @param notifications [Array] Array of notification objects
    # @return [Array<Copilot::Notification>] Array of wrapped notifications with subject data
    def create_copilot_notifications(notifications)
      notifications.map do |notification|
        Copilot::Notification.new(
          notification: notification,
          user: user
        )
      end
    end

    # Extract JSON from a string that may be wrapped in markdown code fences
    # @param text [String] The text that may contain JSON wrapped in ```json ... ```
    # @return [String] The extracted JSON string
    def extract_json(text)
      # Remove markdown code fences if present (e.g., ```json ... ``` or ``` ... ```)
      text.gsub(/\A```(?:json)?\s*\n?/, "").gsub(/\n?```\s*\z/, "").strip
    end
  end
end
