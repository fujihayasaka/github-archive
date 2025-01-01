# typed: true
# frozen_string_literal: true

module Reminders
  class MentionFinder
    def self.events(body:, actor:, pull_request:, subject:, url:)
      new(body, actor, pull_request, subject, url).events
    end

    attr_reader :body, :actor, :organization, :pull_request, :subject, :type, :context
    def initialize(body, actor, pull_request, subject, url)
      @body = body
      @actor = actor
      @pull_request = pull_request
      @subject = subject

      @organization = pull_request.repository.owner
      @type = :mention
      @context = { comment_body: body, comment_html_url: url }
    end

    def events
      return [] unless valid?

      reminders.map do |reminder|
        Reminders::RealTimeEvent.new(
          actor: actor,
          context: context,
          type: type,
          pull_request_ids: [pull_request.id],
          reminder: reminder,
          repository_id: pull_request.repository_id,
          subject: subject,
        )
      end
    end

    def reminders
      @reminders ||= PersonalReminder.
        for_remindable(organization).
        for_event_type(type).
        where(user_id: mentioned_user_ids).
        where.not(user_id: actor.id)
    end

    def valid?
      actor && body.present?
    end

    def mentioned_user_ids
      @mentioned_user_ids ||= User.where(login: mentioned_logins.uniq).pluck(:id)
    end

    def mentioned_logins
      return @mentioned_logins if defined?(@mentioned_logins)

      @mentioned_logins = []
      GitHub::HTML::MentionFilter.mentioned_logins_in(body) do |_, login, _|
        @mentioned_logins << login
      end

      @mentioned_logins
    end
  end
end
