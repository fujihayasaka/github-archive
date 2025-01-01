# typed: true
# frozen_string_literal: true

module Notifyd
  # TODO: move to email dir as email/header.rb
  class EmailHeaders
    def initialize(subject, subject_parent, actor_login)
      @subject = subject
      @subject_parent = subject_parent
      @actor_login = actor_login
      @list_id = nil
      @list_archive = nil
    end

    def with_in_reply_to(in_reply_to)
      @in_reply_to = in_reply_to
      self
    end

    def with_reply_to(reply_to)
      @reply_to = reply_to.to_s
      self
    end

    def with_list_id(custom_list_id)
      @list_id = custom_list_id
      self
    end

    def with_list_archive(custom_list_archive)
      @list_archive = custom_list_archive
      self
    end

    def build
      {
        "Message-ID": message_id,
        "Reply-To": reply_to,
        "In-Reply-To": in_reply_to,
        "References": in_reply_to,
        "Precedence": "list",
        "Return-Path": "<#{GitHub.urls.noreply_address}>",
        "X-GitHub-Sender": actor_login,
        "List-Id": list_id,
        "List-Archive": list_archive,
        "List-Post": mail_replies_address,
        "Date": Time.now.to_formatted_s(:rfc822),
      }.compact
    end

    private

    attr_reader :actor_login, :reply_to, :in_reply_to, :subject, :subject_parent

    def message_id
      @subject.message_id # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    end

    def list_id
      return @list_id if @list_id.present?

      address = "<#{subject_parent.name}.#{subject_parent.owner&.display_login}.#{GitHub.urls.host_name}>"
      "#{subject_parent.name_with_display_owner} #{address}"
    end

    def list_archive
      return @list_archive if @list_archive.present?

      subject_parent.permalink
    end

    def mail_replies_address
      GitHub.urls.noreply_address
    end
  end
end
