# typed: false
# frozen_string_literal: true

# The base class for all Stratocaster::Event views is responsible for
# finding the appropriate view for an event type and rendering/caching
# its partial template.
#
# These views are decorators over Stratocaster::Event instances that add
# view related methods, while delegating all other method calls to the event.
#
# This also normalizes access to common event attributes like repository, actor,
# and payload. Older events don't have the same hash keys and layout as newer
# events, so we need one place to convert the old schema into something sensible.
#
# We should update the older data so we only have one schema per event type to
# deal with. Until that happens, we'll deal with backwards compatibility here.
module Events
  class View < SimpleDelegator
    include Scientist

    REPO_DESCRIPTION_MAX_LENGTH = 150

    # Internal: Call various text and application helpers through this
    # object.
    def helpers
      @helpers ||= ViewModel::Helpers.new(self)
    end

    # Decorate a list of event objects with a view model.
    #
    # events - An Array of Stratocaster::Events to decorate with their
    #          appropriate Events::View subclasses.
    #
    # Returns an Array of Events::View subclasses.
    def self.decorate(events)
      events.flatten.compact.map { |event| self.for(event) }
    end

    # List with the event types we have views to render
    RENDER_VIEWS = [
      Stratocaster::Event::COMMIT_COMMENT_EVENT,
      Stratocaster::Event::CREATE_EVENT,
      Stratocaster::Event::DELETE_EVENT,
      Stratocaster::Event::FOLLOW_EVENT,
      Stratocaster::Event::FORK_EVENT,
      Stratocaster::Event::GOLLUM_EVENT,
      Stratocaster::Event::ISSUE_COMMENT_EVENT,
      Stratocaster::Event::ISSUES_EVENT,
      Stratocaster::Event::MEMBER_EVENT,
      Stratocaster::Event::PUBLIC_EVENT,
      Stratocaster::Event::PULL_REQUEST_EVENT,
      Stratocaster::Event::PULL_REQUEST_REVIEW_COMMENT_EVENT,
      Stratocaster::Event::PUSH_EVENT,
      Stratocaster::Event::RELEASE_EVENT,
      Stratocaster::Event::SPONSOR_EVENT,
      Stratocaster::Event::WATCH_EVENT,
    ].freeze

    # Decorate the event with its view. The view class is matched to the
    # event based on its `event_type` attribute. For example, an 'IssuesEvent'
    # would be wrapped with an IssuesView instance.
    #
    # event - The Stratocaster::Event to decorate.
    # grouped - Boolean indicating if this event is shown in a group of other similar events in
    #           the news feed.
    #
    # Examples
    #
    #   event = Events::View.for(event) # => PushView
    #   render_event(event) # => "html . . ."
    #
    # Returns the event decorated with an Events::View subclass.
    def self.for(event, grouped: false)
      if event.event_type.in?(RENDER_VIEWS)
        name = event.event_type.sub("Event", "View")
        klass = "Events::#{name}".constantize
      else
        klass = Events::NilView
      end

      klass.new(event, grouped: grouped)
    end

    # View subclasses can use this to access the original, undecorated, object.
    # This is equivalent to using SimpleDelegator's __getobj__ method, but much
    # prettier.
    attr_reader :model

    # Is this event being rendered as part of a group of similar events in the news feed?
    attr_reader :grouped

    # Wrap a model object with a view decorator that adds behavior needed
    # for view generation.
    #
    # model - An object to decorate, typically an ActiveModel.
    # grouped - Boolean indicating if this event is shown in a group of other similar events in
    #           the news feed.
    def initialize(model, grouped: false)
      @model, @grouped = model, grouped
      super(model) # pretty
    end

    # Rails helpers, like link_to and url_for, call this method to convert the
    # object into an ActiveModel instance. This lets the view get out of
    # the way of normal Rails usage.
    def to_model
      model
    end

    def action
      super&.to_s
    end

    # Do not call this. Seriously. Use the Hash returned by `repo` or dig through `payload` to
    # find the repository info.
    #
    # Returns the Repository related to the event.
    # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
    def repository
      @repository ||= unless defined?(@repository)
        Repository.find_by_id(repo[:id] || 0)
      end
    end
    # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

    # Returns a Hash of user data that owns the repository affected by the event.
    def user
      @user ||= (model.user || {}).with_indifferent_access
    end

    # Returns a Hash of repository data related to this event.
    def repo
      @repo ||= (model.repo || {}).with_indifferent_access
    end

    # Returns a Hash of event API payload data. Because it's used by the API,
    # this frequently contains all the information needed to build an HTML view
    # of the event as well, without querying the database.
    def payload
      @payload ||= (model.payload || {}).with_indifferent_access
    end

    def actor_text
      actor_login || "(deleted)"
    end

    def repo_text
      repo_nwo || "(deleted)"
    end

    def pusher_text
      case pusher_type.to_s
      when "user", "" then actor_text
      when "deploy_key" then "A deploy key"
      else
        raise ArgumentError, "Invalid pusher type: #{pusher_type.class}"
      end
    end

    def formatted_repo_description
      if repo_description.present?
        formatted = GitHub::Goomba::DescriptionPipeline.to_html(repo_description)
        HTMLTruncator.new(formatted, REPO_DESCRIPTION_MAX_LENGTH).to_html(wrap: false)
      end
    end

    def show_event_details?(viewer:)
      false
    end

    def repo_help_wanted_issues_count
      super.to_i
    end

    def repo_language
      Linguist::Language[repo_language_name]
    end

    def repo_stargazers_count
      super.to_i
    end

    def repo_stargazers_path
      "/#{repo_nwo}/stargazers" if repo_nwo
    end

    def help_wanted_issues_path
      return unless repo_nwo

      name = help_wanted_label_name || "help wanted"
      param = { q: "label:\"#{name}\" is:open is:issue" }
      repo_path = repo_nwo.split("/").map { |segment| UrlHelper.escape_path(segment) }.join("/")
      "/#{repo_path}/issues?" + param.to_param
    end

    def repo_pushed_on
      return unless repo_pushed_at.present?

      date = Date.parse(repo_pushed_at)
      format = if date.year == Date.today.year
        "%b %-d"
      else
        "%b %-d, %Y"
      end
      date.strftime(format)
    end

    def actor_bot_identifier_text
      return unless sender_record.is_a?(Bot) || sender_record.is_a?(PlatformTypes::Bot)
      "bot"
    end

    def pusher_bot_identifier_text
      case pusher_type.to_s
      when "user", ""
        actor_bot_identifier_text
      end
    end

    # Public: Should anything be rendered for this event? Can be overridden by child classes.
    def should_render?
      true
    end

    # Internal: Call generated route and URL helpers through this
    # object.
    def urls
      @urls ||= ViewModel::URLs.new
    end

    def view_attributes(org_id:, viewer:)
      NewsFeedAnalytics.event_view_attributes(
        model,
        event_details: event_details(viewer: viewer),
        org_id: org_id,
        viewer_id: viewer&.id,
      )
    end

    def analytics_attributes_for(target, org_id:, viewer:)
      NewsFeedAnalytics.event_click_attributes(
        model,
        event_details: event_details(viewer: viewer),
        target: target,
        org_id: org_id,
        viewer_id: viewer&.id,
      )
    end

    # event details for event analytics
    def event_details(viewer:)
      {
        additional_details_shown: show_event_details?(viewer: viewer),
        grouped: grouped,
      }
    end

    def partial_path
      event_type = self.event_type.chomp("Event").underscore
      "events/#{event_type}"
    end

    def icon
      kind
    end

    def user_is_sponsorable?(sponsorable_user_ids, viewer:)
      return false unless GitHub.sponsors_enabled?
      return false unless sponsorable_user_ids.present?
      return false unless respond_to?(:sponsor_button_target_user_id)
      return false if viewer.id == sponsor_button_target_user_id
      sponsorable_user_ids.include?(sponsor_button_target_user_id)
    end

    private

    # Convert Markdown formatted text into HTML, truncating it to a reasonable
    # size if needed.
    #
    # text - The String of Markdown text to convert and truncate.
    # max  - The Integer maximum length of the HTML.
    #
    # Returns the html safe truncated HTML String.
    def truncate_html(text, max)
      HTMLTruncator.new(full_html(text), max).to_html
    end

    # Convert the Markdown formatted text into HTML.
    #
    # text - The String of Markdown text to convert.
    #
    # Returns a Nokogiri::HTML::DocumentFragment.
    def full_html(text)
      # repository makes sha and issue links work
      context = { entity: repository }
      result = GitHub::Goomba::MarkdownPipeline.call(text, context)
      GitHub::HTML.parse(result[:output])
    end

    # Report cache miss or hit to monitoring service
    #
    # cached - Boolean
    # event_name - The String describing the event
    # version - The String describing the version of the content that was cached
    def report_events_cache_event(cached, event_name, version)
      type = cached ? "hit" : "miss"
      tags = ["type:#{type}", "version:#{version}"]
      GitHub.dogstats.increment("events.render.cache", tags: tags)
    end

    # Trace which methods are delegated to Stratocaster::Event
    def method_missing(method_name, *)
      GitHub.dogstats.increment(
        "stratocaster.view_model_delegation",
        tags: [
          "class:#{self.class}",
          "delegate_class:#{model.class}",
          "method:#{method_name}",
        ],
      )

      super
    end
  end
end
