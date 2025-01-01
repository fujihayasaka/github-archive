# typed: true
# frozen_string_literal: true

module Events
  # This view model class does not decorate any Stratocaster event type. It's
  # the model that provides logic to the views/events/index.atom.erb template.
  class AtomView
    attr_reader :view

    def initialize(view)
      @view = view
      # gross
      @feed_title = view.instance_variable_get(:@feed_title)
      @event_feed_user = view.instance_variable_get(:@event_feed_user)
    end

    def cache_key
      latest = current_events.first
      id = latest ? latest.id : 0
      "feeds:%s:%s" % [Digest::SHA256.hexdigest(view.request.url), id]
    end

    def feed_id
      path = view.request.fullpath.split(".")[0]
      ["tag:", GitHub.host_name, ",2008:", path].tap do |id|
        id << ".private" if view.params[:action] == "private_feed"
        id << ".actor" if view.params[:action] == "private_actor_feed"
      end.join
    end

    def feed_title
      @feed_title || "GitHub Public Timeline Feed"
    end

    def self_url
      view.request.url
    end

    def html_url
      view.request.url.split(".atom")[0].chomp(".actor").chomp(".private")
    end

    def feed_updated_at
      if current_events.empty?
        (view.current_user.try(:created_at) || Time.now.utc).iso8601
      else
        current_events.first.created_at.iso8601
      end
    end

    def events
      current_events.map do |event|
        event = if event.is_a?(Conduit::FeedItem)
          Conduit::StratocasterEventAdapter.for(event)&.new(event, view)
        else
          AtomEvent.new(event, view)
        end
        event if event&.valid?
      end.compact
    end

    private

    def current_events
      view.current_events
    end

    class AtomEvent
      attr_reader :event, :view

      def initialize(event, view)
        @event, @view = event, view
      end

      def published_at
        event.created_at.iso8601
      end

      def updated_at
        event.created_at.iso8601
      end

      def id
        "tag:%s,2008:%s/%s" % [GitHub.host_name, event.event_type, event.id]
      end

      # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
      def author
        @author ||= unless defined?(@author)
          anon = User::AvatarList.anonymous_user("(anonymous)")
          user = event.sender_record || @event_feed_user || anon
          Author.new(user, view)
        end
      end
      # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

      def html_url
        url = event.url || author.url
        url = "#{GitHub.url}#{url}" unless url =~ /^http/
        url
      end

      # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
      def content
        @content ||= unless defined?(@content)
          begin
            if content = view.render_event(event_view)
              content = content.gsub(/<div class="gravatar">.+?<\/div>/, "") # rubocop:disable Rails/ViewModelHTML
              content.scrub
              GitHub::Goomba::NoReferrerPipeline.to_html(content, {})
            end
          rescue => ex # rubocop:todo Lint/GenericRescue
            GitHub.dogstats.increment("event", tags: ["action:render", "result:failure"])
            Failbot.report(ex, event: event, payload: event.payload)
            raise if Rails.env.development? || Rails.env.test?
            nil
          end
        end
      end
      # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

      def title
        event_view.title_text
      end

      def valid?
        content.present?
      end

      private

      def event_view
        @event_view ||= Events::View.for(event)
      end

      class Author
        attr_reader :email, :gravatar, :login, :name, :url
        def initialize(user, view)
          login     = user.display_login.scrub
          @login    = login
          @name     = login
          @email    = user.profile_email
          @gravatar = view.avatar_url_for(user, 30)
          @url      = "%s/%s" % [GitHub.url, login]
        end
      end
    end
  end
end
