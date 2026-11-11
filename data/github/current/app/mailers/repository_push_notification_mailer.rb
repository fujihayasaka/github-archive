# typed: true
# frozen_string_literal: true

class RepositoryPushNotificationMailer < ApplicationMailer
  include UrlHelpers # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  include UrlHelper # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  include Pushes::CommitsHelper

  self.mailer_name = "mailers/repository_push_notification"
  helper_method :commit_author, :commit_changes, :commits_pushed, :compare_url_string, :repository, :ref, :commits_pushed_limited

  attr_reader :before, :after, :ref, :repository, :first_commit, :last_commit, :pusher


  # Public class method: determine the actual recipient list from the hook config
  #
  # Legacy hook configs may not have been properly validated, and so may not just contain
  # "two emails separated by whitespace"
  #
  # In practice we actually deliver email to the first two "strings" separated by whitespace,
  # which may contain more than two emails if they are separated by commas/semicolons
  #
  # Return an array of emails for delivery
  def self.recipients_from_config(address_config)
    return [] unless address_config

    first_two = address_config.split(" ").slice(0, 2)

    # use the mail gem (which the mailer uses under the hood) to parse recipients
    Array(Mail.new(to: first_two).to)
  end

  # Public: Sends email notification on push event when configured on a repository.
  #
  # This replaces the legacy `email` service from `github-services`.
  # See https://github.com/github/experience-product/issues/114 for more detail
  #
  # Returns a Mail instance to deliver.
  def build(before:, after:, ref:, repository:, pusher:, secret:, address:)
    @before = before
    @after = after
    @ref = ref
    @repository = repository
    @pusher = pusher

    @first_commit = commits_pushed.first
    @last_commit = commits_pushed.last # assume that the last committer is also the pusher

    @unsubscribe_url = get_unsubscribe_url(@repository)
    headers["List-Unsubscribe"] = "<#{@unsubscribe_url}>"

    recipients = RepositoryPushNotificationMailer.recipients_from_config(address)

    # Set Approved header to secret set in hook config attributes, if exists.
    headers["Approved"] = secret if secret.to_s.size > 0
    headers["X-GitHub-Recipient-Address"] = recipients.join(",")

    mail(
      from: github_noreply(last_commit&.author || pusher),
      to: recipients,
      subject: mail_subject,
      message_id: message_id,
    )
  end

  private

  # Private: returns subject string for mailer
  #
  # first_commit may not exist. For example, pushing a new tag would not contain
  # any commits, resulting in `first_commit` being nil.
  #
  # Return String
  def mail_subject
    if first_commit
      title_line = first_commit.message[/\A[^\n]+/] || ""

      "[#{repository.name_with_display_owner}] #{first_commit.oid.slice(0, 6)}: #{title_line.truncate(53)}"
    else
      "[#{repository.name_with_display_owner}]"
    end
  end

  # Private: returns array of commit changes
  #
  # Build and sort an array of commit changes from a commit instance.
  #
  # commit - A Commit instance.
  #
  # Returns Array
  def commit_changes(commit)
    changes = commit.init_diff.deltas.inject([]) do |memo, delta|
      case delta.status
      when "A"
        memo << ["A", force_encoding(delta.new_file.path)]
      when "D"
        memo << ["R", force_encoding(delta.old_file.path)]
      when "R"
        memo << ["A", force_encoding(delta.new_file.path)]
        memo << ["R", force_encoding(delta.old_file.path)]
      else
        memo << ["M", force_encoding(delta.new_file.path)]
      end
    end

    changes.sort_by { |(_char, file)| file }
  end

  # Private: file paths must be force-encoded to utf-8 since they
  # are returned from git as binary strings
  def force_encoding(str)
    str.dup.force_encoding("UTF-8").scrub!
  end

  # Private: returns author string for use in mailer body.
  #
  # Use author to build author string. If a commit author
  # does not exist then we return N/A.
  #
  # commit - A Commit instance.
  #
  # Returns String
  def commit_author(commit)
    return "N/A" unless commit.author_name && commit.author_email

    "#{commit.author_name} <#{commit.author_email}>"
  end

  # Private: build a message id to pass along as the `Message-ID` header
  #
  # Includes the repo owner/name, ref pushed, and the before/after commit sha if relevant
  #
  # e.g. "<github/github/push/ref/heads/master/ab1234-cd5678@github.com>"
  #
  # Returns String
  def message_id
    compare_string = "#{before.slice(0, 6)}-#{after.slice(0, 6)}"
    "<#{repository.name_with_display_owner}/push/#{ref}/#{compare_string}@#{GitHub.urls.host_name}>"
  end

  # Builds the absolute URL for comparison.
  #
  # Returns a String URL.
  def compare_url_string
    @compare_url ||= if !created?
      compare_url(repository.owner, repository, "#{before[0, 12]}...#{after[0, 12]}")
    elsif commits_pushed.length > 1
      # If the push created a new branch, we want to use the parent of the first commit
      compare_url(repository.owner, repository, "#{T.must(commits_pushed.first).oid[0, 12]}^...#{T.must(commits_pushed.last).oid[0, 12]}")
    end
  end

  # Builds the absolute URL for a commit.
  #
  # commit - A Commit Instance.
  #
  # Returns a String URL.
  def commit_url(commit)
    # The default routing method commit_url is overwritten by UrlHelper
    # which does not include the host. As a result we need to access the
    # method directly.
    UrlHelpers.commit_url(repository.owner, repository, commit, host: GitHub.url)
  end

  # Builds the absolute URL for unsubscribe settings
  #
  # repo - A Repository Instance.
  #
  # Returns a String URL.
  def get_unsubscribe_url(repo)
    UrlHelpers.repository_notification_settings_url(repository.owner, repository, host: GitHub.url)
  end
end
