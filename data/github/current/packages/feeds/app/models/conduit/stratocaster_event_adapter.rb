# typed: true
# frozen_string_literal: true

module Conduit
  # This class is a thin adapter for Conduit Events to be used in place of
  # Stratocaster events.
  class StratocasterEventAdapter < SimpleDelegator
    include GitHub::Memoizer

    EVENT_ADAPTERS = {
      FeedItem::PublishedRelease                => EventAdapter::Release,
      FeedItem::CreatedPullRequest              => EventAdapter::PullRequest,
      FeedItem::ClosedPullRequest               => EventAdapter::PullRequest,
      FeedItem::MergedPullRequest               => EventAdapter::PullRequest,
      FeedItem::ReopenedPullRequest             => EventAdapter::PullRequest,
      FeedItem::AssignedPullRequest             => EventAdapter::PullRequest,
      FeedItem::UnassignedPullRequest           => EventAdapter::PullRequest,
      FeedItem::RequestedReviewPullRequest      => EventAdapter::PullRequest,
      FeedItem::MemberAddToRepository           => EventAdapter::Member,
      FeedItem::StarredRepository               => EventAdapter::StarredRepository,
      FeedItem::PublishedWiki                   => EventAdapter::Wiki,
      FeedItem::SponsoredUser                   => EventAdapter::Sponsor,
      FeedItem::SponsorableUser                 => EventAdapter::Sponsor,
      FeedItem::PushEvent                       => EventAdapter::PushEvent,
      FeedItem::CreatedPullRequestReviewComment => EventAdapter::PullRequestReviewComment,
      FeedItem::CreatePush                      => EventAdapter::CreatePush,
      FeedItem::DeletePush                      => EventAdapter::DeletePush,
      FeedItem::AssignedIssue                   => EventAdapter::Issue,
      FeedItem::UnassignedIssue                 => EventAdapter::Issue,
      FeedItem::CreatedIssue                    => EventAdapter::Issue,
      FeedItem::ClosedIssue                     => EventAdapter::Issue,
      FeedItem::ReopenedIssue                   => EventAdapter::Issue,
      FeedItem::LabeledIssue                    => EventAdapter::Issue,
      FeedItem::UnlabeledIssue                  => EventAdapter::Issue,
      FeedItem::CommentedIssue                  => EventAdapter::CommentedIssue,
      FeedItem::ForkedRepository                => EventAdapter::Fork,
      FeedItem::CommentedCommit                 => EventAdapter::CommentedCommit,
      FeedItem::PrivateToPublicRepository       => EventAdapter::PrivateToPublicRepository,
    }.freeze

    def self.for(feed_item)
      EVENT_ADAPTERS.fetch(feed_item.class, nil)
    end

    def initialize(feed_item, view)
      T.bind(self, T.untyped)
      super(feed_item)
      @view = view
    end

    def valid?
      T.bind(self, T.untyped)
      subject.present? && actor.present?
    end

    def published_at
      T.bind(self, T.untyped)
      created_at
    end

    def updated_at
      T.bind(self, T.untyped)
      created_at
    end

    def author
      T.bind(self, T.untyped)
      Author.new(actor, view)
    end

    memoize def content
      feed_item_type = __getobj__.class.name.demodulize.underscore
      GitHub.dogstats.distribution_time("conduit.timeline.event_render_time", tags: ["feed_item_type:#{feed_item_type}"]) do
        content = view.render_event(self)
        return nil if content.nil?

        content = content.gsub(/<div class="gravatar">.+?<\/div>/, "")
        content.scrub
        GitHub::Goomba::NoReferrerPipeline.to_html(content, {})
      end
    end

    def should_render?
      valid?
    end

    def grouped
      false
    end

    def sender_record
      T.bind(self, T.untyped)
      actor
    end

    def actor_login
      T.bind(self, T.untyped)
      actor.display_login.scrub
    end

    def view_attributes(_)
      {}
    end

    def title
      T.bind(self, T.untyped)
      raise NotImplementedError.new("Expected subclass #{self.class} to implement #{__method__}")
    end

    def html_url
      T.bind(self, T.untyped)
      raise NotImplementedError.new("Expected subclass #{self.class} to implement #{__method__}")
    end

    def partial_path
      T.bind(self, T.untyped)
      raise NotImplementedError.new("Expected subclass #{self.class} to implement #{__method__}")
    end

    def icon
      T.bind(self, T.untyped)
      raise NotImplementedError.new("Expected subclass #{self.class} to implement #{__method__}")
    end

    def id
      T.bind(self, T.untyped)
      "tag:#{GitHub.host_name},2008:#{event_type}/#{event_id}"
    end

    private

    attr_reader :view

    class Author
      attr_reader :email, :gravatar, :login, :name, :url

      def initialize(user, view)
        login = user.display_login.scrub
        @login = login
        @name = login
        @email = user.profile_email
        @gravatar = view.avatar_url_for(user, 30)
        @url = "#{GitHub.url}/#{login}"
      end
    end
  end
end
