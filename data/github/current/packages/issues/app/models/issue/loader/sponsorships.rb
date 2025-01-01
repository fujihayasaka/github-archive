# typed: true
# frozen_string_literal: true

class Issue::Loader::Sponsorships < Issue::Loader::Base
  def initialize(context, issue:, issue_comments: [])
    @context = context
    @issue = issue
    @issue_comments = issue_comments
  end

  def self.load_for(context, issue:, issue_comments: [])
    super new(context, issue: issue, issue_comments: issue_comments)
  end

  def load
    return unless GitHub.sponsors_enabled?

    is_listed = Platform::Loaders::SponsorsListingCheck.load(@issue.owner.id).sync
    if is_listed
      sponsors_by_author = Hash.new
      issue_sponsor_promise = Platform::Loaders::SponsorshipByCommentAuthorId.
        load(@context.viewer, @issue.owner, @issue.user_id).then do |result|
          sponsors_by_author[@issue.user_id] = result
        end

      comments_sponsors_promises = @issue_comments.
        map do |comment| Platform::Loaders::SponsorshipByCommentAuthorId.
          load(@context.viewer, @issue.owner, comment.user_id).then do |result|
            sponsors_by_author[comment.user_id] = result
          end
        end

      Promise.all([issue_sponsor_promise] + comments_sponsors_promises).then do
        @context.preload_attr(:author_to_repo_owner_sponsorships_by_author_id, sponsors_by_author)
      end.sync
    end
  end
end
