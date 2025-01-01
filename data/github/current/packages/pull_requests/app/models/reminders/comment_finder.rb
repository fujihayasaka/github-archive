# typed: true
# frozen_string_literal: true

module Reminders
  class CommentFinder
    def self.events(actor:, body:, pull_request:, subject:, url:)
      new(actor, body, pull_request, subject, url).events
    end

    attr_reader :actor, :body, :context, :organization, :pull_request, :subject, :type
    def initialize(actor, body, pull_request, subject, url)
      @actor = actor
      @body = body
      @pull_request = pull_request
      @subject = subject

      @organization = pull_request&.repository&.organization
      @context = { comment_body: body, comment_html_url: url }
      @type = :comment
    end

    def reminders
      @reminders ||= PersonalReminder.
        for_remindable(organization).
        for_event_type(type).
        where(user_id: pull_request.user_id).
        where.not(user_id: actor.id)
    end

    def valid?
      pull_request && organization && body.present?
    end

    def events
      return [] unless valid?

      reminders.map do |reminder|
        Reminders::RealTimeEvent.new(
          actor: actor,
          context: context,
          type: type,
          reminder: reminder,
          pull_request_ids: [pull_request.id],
          repository_id: pull_request.repository_id,
          subject: subject,
        )
      end
    end
  end
end
