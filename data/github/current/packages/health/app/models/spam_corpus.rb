# typed: true
# frozen_string_literal: true

class SpamCorpus < ApplicationRecord::Domain::Spam
  belongs_to :source, polymorphic: true
  belongs_to :source_user, class_name: "User"

  belongs_to :owner, class_name: "User"

  validates_presence_of :data
  validates_inclusion_of :spam, in: [true, false]

  scope :spammy, -> { where(spam: true) }
  scope :hammy, -> { where(spam: false) }

  MAX_DATA_SIZE = 65535   # BLOB size by default

  # gist = Gist.find 37
  # SpamCorpus.from_gist(gist, true)  # It's spam, bleah.
  # SpamCorpus.from_gist(gist, false) # It's ham, yum!
  def self.from_gist(gist, spam, options = {})
    # For the moment, we only grab the contents of the first file in a Gist.
    # This is because spammers don't (yet) typically push the content down
    # into subsequent files. Presumably this is so their content will be
    # shown in the discover view and "above the fold" in a gist show view.
    blob = gist.files_with_path.first.first

    # Sometimes gists -- especially spammy ones -- don't have much in the
    # body and try to spam it up with just a description. Or the body may
    # consist entirely of image tags. So we'll just tack the description
    # on the front of our scorable data.
    data = "#{gist.description}"
    data_size = MAX_DATA_SIZE - 1 - data.length
    data += blob.data[0..data_size]

    # If the original Gist has a user, store the id here, in case the
    # Gist gets deleted later (spammers like doing this).
    args = { data: data, spam: spam,
             source: gist, source_user_id: gist.user_id }

    # If we were passed the User record of the Hubber adding this record,
    # stuff it in here, too.
    args[:owner] = options[:user] if options[:user].is_a? User

    SpamCorpus.new(args)
  end

  # comment = GistComment.find 37 (or CommitComment or IssueComment)
  # SpamCorpus.from_comment(comment, true)  # It's spam, bleah.
  # SpamCorpus.from_comment(comment, false) # It's ham, yum!
  def self.from_comment(comment, spam, options = {})
    args = { data: comment.body, spam: spam, source: comment,
             source_user_id: comment.user_id }

    # If we were passed the User record of the Hubber adding this record,
    # stuff it in here, too.
    args[:owner] = options[:user] if options[:user].is_a? User

    SpamCorpus.new(args)
  end

  # issue = Issue.find 37
  # SpamCorpus.from_issue(issue, true)  # It's spam, bleah.
  # SpamCorpus.from_issue(issue, false) # It's ham, yum!
  def self.from_issue(issue, spam, options = {})
    data = [issue.title, issue.body].reject(&:blank?).join("\n")
    args = { data: data, spam: spam, source: issue,
             source_user_id: issue.user_id }

    # If we were passed the User record of the Hubber adding this record,
    # stuff it in here, too.
    args[:owner] = options[:user] if options[:user].is_a? User

    SpamCorpus.new(args)
  end
end
