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
      @labels = nil
      @milestone = nil
      @assignees = nil
      @issue_type = nil
      @issue_state = nil
      @pull_request_status = nil
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

    def with_labels(labels)
      @labels = labels
      self
    end

    def with_milestone(milestone)
      @milestone = milestone
      self
    end

    def with_assignees(assignees)
      @assignees = assignees
      self
    end

    def with_issue_type(issue_type)
      @issue_type = issue_type
      self
    end

    def with_issue_state(issue_state)
      @issue_state = issue_state
      self
    end

    def with_pull_request_status(pull_request_status)
      @pull_request_status = pull_request_status
      self
    end

    def build
      headers = {
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
        "X-GitHub-Labels": labels_header_value,
        "X-GitHub-Milestone": milestone_header_value,
        "X-GitHub-Assignees": assignees_header_value,
        "X-GitHub-IssueType": issue_type_header_value,
        "X-GitHub-IssueState": issue_state_header_value,
        "X-GitHub-PullRequestStatus": pull_request_status_header_value
      }

      headers.compact
    end

    private

    attr_reader :actor_login, :reply_to, :in_reply_to, :subject, :subject_parent, :labels, :milestone, :assignees, :issue_type, :issue_state, :pull_request_status

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

    def labels_header_value
      return nil unless labels&.any?

      labels.map(&:name).join("; ")
    end

    def milestone_header_value
      return nil unless @milestone.present?

      @milestone.title
    end

    def assignees_header_value
      return nil unless @assignees&.any?

      @assignees.map(&:display_login).join("; ")
    end

    def issue_type_header_value
      return nil unless @issue_type.present?

      @issue_type.name
    end

    def issue_state_header_value
      return nil unless @issue_state.present?

      @issue_state
    end

    def pull_request_status_header_value
      return nil unless @pull_request_status.present?

      @pull_request_status
    end
  end
end
