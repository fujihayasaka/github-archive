# typed: false
# frozen_string_literal: true

require "set"
require "scientist"

module GitHub
  # Mixin adds HTML filtering related methods to models and other stuff
  # that has a #body attribute.
  #
  # Classes that include UserContent MUST have a `new_record?` method
  # and a `body` method
  module UserContent
    extend ActiveSupport::Concern
    include GitHub::BatchMethod
    include GitHub::Memoizer

    BODY_CACHE_VERSION = 72
    DEFAULT_CACHE_SETTINGS = {
      use_cache: false,
      cache_partition: :usercontent,
      cache_result_keys: [:task_list_summary, :mentioned_usernames],
    }.freeze

    module ClassMethods
      def setup_attachments
        has_many :attachments, as: :attachable
        after_save :attach_matching_assets, if: :attach_matching_assets?
      end
    end

    included do
      self.extend ClassMethods
      self.send(:include, GitHub::Validations)
      batch_method(:prelude_body_html) do |content_pieces, options|
        result = Promise.all(
          content_pieces.map { |content| content.async_body_html(context: options[:context]) }
        ).sync # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        content_pieces.zip(result).to_h
      end
    end

    def body_result(context: {}, cache_settings: {})
      async_body_result(context: context, cache_settings: cache_settings).sync # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    end

    def async_body_result(context: {}, cache_settings: {})
      @body_result_cache ||= {}

      async_body_context
      .then { |body_context| body_context.merge(context) }
      # preload the entity's owner, but keep the context as the chained promise value
      .then { |context| context[:entity].try(:async_owner).then { context } }
      .then do |context|
        cache_settings = DEFAULT_CACHE_SETTINGS.merge(cache_settings)
        cache_settings[:cache_prefix] = body_cache_key_prefix(:html)
        cache_settings[:cache_result_keys] += GitHub::Goomba::WarpPipeCaching::DEFAULT_RESULT_CACHE_KEYS

        # allow callers to override the pipeline that is used
        pipeline = context.delete(:body_pipeline) || body_pipeline

        # use a separate cache key for cached vs uncached values,
        # because results loaded from the cache will not be fully hydrated
        body_result_cache_key_prefix = cache_settings[:cache_prefix]
        body_result_cache_key_prefix += ":uncached" unless cache_settings[:use_cache]
        cache_key = pipeline.cache_key(context, body, body_result_cache_key_prefix, cache_results: cache_settings[:cache_result_keys])

        cached_body_content = @body_result_cache[cache_key]
        next cached_body_content if cached_body_content.present?

        @body_result_cache[cache_key] = pipeline.async_call(body, context, cache_settings: cache_settings)
      end
    end

    # The body HTML after all filters have been performed.
    #
    # Returns the body HTML as a String
    def body_html(context: {})
      # @body_html exists via `attr_preloadable :body_html` in models
      return @body_html if defined?(@body_html)
      async_body_html(context: context).sync # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    end

    def async_body_html(context: {})
      return Promise.resolve(nil) if body.nil? # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      async_body_result(context: context, cache_settings: { use_cache: true })
        .then { |result| GitHub::HTML::Result.to_html(result) }
    end

    # A text only version of the rendered body HTML. This should be used when
    # showing titles and truncated previews.
    #
    # Returns the textual version of the body HTML.
    def body_text(context: {})
      async_body_text(context:).sync
    end

    def async_body_text(context: {})
      return Promise.resolve(nil) if body.nil?
      async_body_result(context:, cache_settings: { use_cache: true })
        .then { |result| GitHub::HTML::Result.to_text(result) }
    end

    # The body HTML truncated to the given number of visual characters.
    #
    # Returns the truncated body HTML as a String.
    def async_truncated_body_html(max,
      strip_block_elements: true,
      strip_heading_elements: false,
      keep_svg_elements: false,
      strip_formatted_elements: false,
      wrap: true,
      context: {}
    )
      async_body_html(context: context).then do |html|
        HTMLTruncator.new(html, max, strip_block_elements: strip_block_elements, strip_heading_elements: strip_heading_elements, keep_svg_elements: keep_svg_elements, strip_formatted_elements: strip_formatted_elements).to_html(wrap: wrap)
      end
    end

    # HTML rendering pipeline context information. Filters have no knowledge of
    # the outside world other than the values provided here.
    #
    # Subclasses should override this method to provide different defaults.
    # Filters can put extracted information into the context which would be
    # available after the Promise returned by async_body_result is resolved.
    def async_body_context
      if respond_to?(:entity) && !respond_to?(:async_entity)
        raise "Responds to #entity but not to #async_entity!"
      end

      Promise.all([
        respond_to?(:async_organization) ? async_organization : Promise.resolve(nil),
        respond_to?(:async_entity) ? async_entity : Promise.resolve(nil),
        async_body_context_user,
        async_body_context_location,
      ]).then do |organization, entity, body_context_user, location|
        {
          subject: self,
          entity: entity,
          organization: organization,
          current_user: body_context_user,
          base_url: GitHub.url,
          asset_root: "#{GitHub.asset_host_url}/images/icons",
          asset_proxy: GitHub.image_proxy_url,
          disable_asset_proxy: !GitHub.image_proxy_enabled?,
          location: location,
        }
      end
    end

    def async_body_context_user
      if respond_to?(:async_latest_user_content_edit)
        async_latest_user_content_edit.then do |latest_user_content_edit|
          if latest_user_content_edit
            latest_user_content_edit.async_editor
          elsif respond_to?(:async_user)
            async_user
          end
        end
      elsif respond_to?(:async_user)
        async_user
      end
    end

    # do not call this method inside asynchronous code
    def body_context_user
      @body_context_user ||=
        if respond_to?(:latest_user_content_edit)
          if latest_user_content_edit
            latest_user_content_edit.editor
          elsif respond_to?(:user)
            user
          end
        elsif respond_to?(:user)
          user
        end
    end

    # The location where this Markdown is being rendered affects whether commands like "Closes
    # #1"/"Duplicate of #1" do anything.
    def async_body_context_location
      if is_a?(Issue)
        async_pull_request.then do |pull_request|
          pull_request? ? pull_request.class.name : self.class.name
        end
      elsif is_a?(IssueComment)
        async_issue.then do |issue|
          issue.async_pull_request.then do
            if issue.pull_request?
              "PullRequestComment"
            else
              self.class.name
            end
          end
        end
      else
        Promise.resolve(nil)
      end
    end

    # Cutover date for comments moved to Markdown.
    MARKDOWN_CUTOVER = Time.utc(2009, 4, 20, 19, 0, 0)

    # The HTML pipeline used to render the body to HTML. This may be
    # overridden by subclasses to specify an different pipeline setup.
    #
    # By default, the pipeline varies based on the object's #formatter
    # attribute and creation time. GFM, Email replies, and old Textile bodies
    # are all supported.
    #
    # Returns the GitHub::Goomba::Pipeline object that the body text should be
    # passed through.
    def body_pipeline
      return GitHub::Goomba::EmailPipeline if try(:formatter) == :email
      return GitHub::Goomba::TextilePipeline if legacy_textile_formatter?

      GitHub::Goomba::MarkdownPipeline
    end

    # Body HTML used when sending email notifications. This can be slightly
    # different from the HTML used to display messages on the site.
    #
    # The only case that's different currently is messages sent via email reply.
    # They're stored as plain text and the default body_html pipeline strips
    # quoting, line ends, and applies github specific styles. When sending email
    # notifications for messages generated by email replies we want to use much
    # more conservative HTML formatting rules.
    #
    # Returns a string of HTML.
    def body_html_for_email
      return body_html(context: { for_email: true }) if try(:formatter) != :email

      cache_key = "#{body_cache_key_prefix(:body_html_for_email)}:#{body_version}"
      GitHub.cache.for_partition(:usercontent).fetch(cache_key) do
        ERB::Util.force_escape(body).gsub("\n", "<br>\n")
      end
    end

    # If the body contains html elements that markdown could produce, it
    # considers the body to contain markdown. It also makes sure an anchor tag's
    # href does not equal its content to distinguish pasted urls from markdown
    # urls.
    #
    # Returns a Boolean
    def body_contains_markdown?
      regex = %r{
        </i>|
        </li>|
        </strong>|
        <a\s+href="([^"]+)">(?!\1)[^<]+</a>|
        </em>|
        </h\d>|
        </blockquote>
      }x

      regex =~ body_html
    end

    CONTAINS_SUGGESTION_REGEX = /js-suggested-changes-blob/
    MAY_CONTAIN_SUGGESTION_REGEX = /```suggestion/i

    # If the body contains html elements that only the SuggestedChangesFilter
    # could produce, it considers the body to contain a suggested change.
    #
    # Returns a Boolean
    def body_contains_suggestion?
      !!(CONTAINS_SUGGESTION_REGEX =~ body_html)
    end

    # If the body contains text that implies a suggestion, it considers
    # that the body _may_ contain a suggested change. This could produce false positives
    # which is OK in some cases.
    #
    # Returns a Boolean
    def body_may_contain_suggestion?
      !!(MAY_CONTAIN_SUGGESTION_REGEX =~ body)
    end

    def legacy_textile_formatter?
      created_before_markdown_cutover? && id_low_enough_for_textile?
    end

    # Internal: is `created_at` before 20-Apr-2009?
    def created_before_markdown_cutover?
      respond_to?(:created_at) && (created_at || Time.now) < MARKDOWN_CUTOVER
    end

    # Internal: is this record already in the prod database before 14-Mar-2016?
    def id_low_enough_for_textile?
      if respond_to?(:max_textile_id, true) && max_textile_id
        respond_to?(:id) && (id.nil? || id < max_textile_id)
      else
        false
      end
    end

    # Users mentioned in the body. The GitHub::HTML::MentionFilter must
    # be part of the body pipeline in order for this information to be
    # extracted.
    #
    # Returns the Array of User objects.
    def mentioned_users
      Array body_result.mentioned_users
    end

    # User names mentioned in the body. The GitHub::HTML::MentionFilter must
    # be part of the body pipeline in order for this information to be
    # extracted.
    #
    # Returns the Array of user names.
    def mentioned_usernames
      async_body_result(cache_settings: { use_cache: true })
        .then { |result| Set.new(Array(result[:mentioned_usernames])) }
        .sync # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    end

    # Teams mentioned in the body. The GitHub::HTML::MentionFilter must
    # be part of the body pipeline in order for this information to be
    # extracted.
    #
    # Returns the Array of Team objects.
    def mentioned_teams
      Array body_result.mentioned_teams
    end

    # Issues mentioned in the body. The GitHub::HTML::IssueMentionFilter must
    # be part of the body pipeline in order for this information to be
    # extracted.
    #
    # Returns the Array of Issue objects.
    def mentioned_issues
      Array(body_result.issues).map { |ref| ref.issue }
    end

    # Discussions mentioned in the body. The GitHub::HTML::IssueMentionFilter must
    # be part of the body pipeline in order for this information to be
    # extracted.
    #
    # Returns the Array of Discussion objects.
    def mentioned_discussions
      Array(body_result.discussions).map { |ref| ref.discussion }
    end

    # Public: All tracking blocks detected within the user content on repositories where the tasklist_block
    # feature flag is enabled.
    #
    # Examples
    #
    #  body_result.tracking_blocks # => [{title: "Tasks", items: [#<TrackingBlocks::Issue issue=#<Issue id=123>>, #<TrackingBlocks::DraftIssue draft_issue="Draft issue title">]}, {title: "I am title", items: [#<TrackingBlocks::DraftIssue draft_issue="Draft issue title">]}]
    #
    # Returns the Array of tracking blocks.
    def tracking_blocks
      async_tracking_blocks.sync
    end

    def async_tracking_blocks
      async_body_result.then do |body_result|
        body_result.tracking_blocks
      end
    end

    # Public: Returns the cached TaskList::Summary object.
    def task_list_summary
      async_task_list_summary.sync
    end

    def async_task_list_summary
      # we need to return an empty summary if the result doesn't contain one
      # to support body pipelines that don't run the task list filter like the TextilePipeline
      async_body_result(cache_settings: { use_cache: true })
        .then { |result| result[:task_list_summary] || TaskList::Summary.new([]) }
    end

    # Public: Counts task list items (with optional filter by status)
    #
    # statuses - One or more symbols that, if present, limit the count to matching items.
    #            Default is to count all of them (:complete and :incomplete).
    #
    # Returns the count (a positive integer number)
    def task_list_item_count(*statuses)
      async_task_list_item_count(*statuses).sync
    end

    # Task list summary that don't call full pipeline to avoid unnecessary overhead
    #
    # Returns a Promise resolving to a TaskList::Summary object.
    def async_lightweight_task_list_summary
      context = { body_pipeline: GitHub::Goomba::LightweightTaskListPipeline }

      async_body_result(context: context, cache_settings: { use_cache: true })
        .then { |result| result[:task_list_summary] }
    end

    def lightweight_task_list_item_count
      return @lightweight_task_list_item_count if defined? @lightweight_task_list_item_count
      @lightweight_task_list_item_count = async_task_list_item_count.sync
    end

    def lightweight_complete_task_list_item_count
      return @lightweight_complete_task_list_item_count if defined? @lightweight_complete_task_list_item_count
      @lightweight_complete_task_list_item_count = async_task_list_item_count(statuses: [:complete]).sync
    end

    def async_task_list_item_count(*statuses)
      return Promise.resolve(0) unless TaskList::Filter.task_body_contains_task_list_items?(body)
      return Promise.resolve(0) if has_too_many_tasks?

      async_lightweight_task_list_summary.then do |task_list_summary|
        next task_list_summary.item_count if statuses.compact.empty?

        result = 0
        result += task_list_summary.complete_count if :complete.in?(statuses)
        result += task_list_summary.incomplete_count if :incomplete.in?(statuses)
        result
      end
    end

    # Public: Returns true if there are any task list items.
    def task_list?
      async_task_list?.sync
    end

    # Answer sync the question if a body has a task list item.
    #
    # Returns true if there is at least one task list item matching
    def has_task_list?
      TaskList::Filter.task_body_contains_task_list_items?(body)
    end

    # Has to many items in the body
    #
    # Returns true if there are more then a 100 tasks.
    memoize def has_too_many_tasks?
      TaskList::Filter.too_many_tasks?(body)
    end

    def async_task_list?
      # Use a quick check to see if we have anything here
      # that looks like a task item. If not, we don't try
      # to render the real task list. This saves a lot of
      # time for the common case of no task list.
      return Promise.resolve(false) unless TaskList::Filter.task_body_contains_task_list_items?(body)

      async_lightweight_task_list_summary.then(&:items?)
    end

    def body_asset_matches
      @body_asset_matches ||= AssetScanner.scan(body_html)
    end

    # Internal: Should we try to attach matching assets to the record?
    # Determines if the attach_matching_assets after_save callback is invoked.
    #
    # Returns a Boolean.
    def attach_matching_assets?
      true
    end

    # Overridable by subclasses to determine if assets should be attached
    # in a background job.
    def attach_matching_assets_in_background?
      false
    end

    def attach_matching_assets
      GitHub.dogstats.increment("attach_matching_assets.runs", tags: [
        "class:#{self.class.name.underscore}",
        "in_background:#{attach_matching_assets_in_background?}"
      ])

      if attach_matching_assets_in_background?
        AttachMatchingAssetsJob.perform_later(self) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      else
        GitHub.dogstats.distribution_time("attach_matching_assets.inline.time", tags: [
          "class:#{self.class.name.underscore}",
        ]) do
          @body_asset_matches = @body_content_cache = nil
          Attachment.attach(self, body_asset_matches)
        end
      end
    end

    def body_cache_key_prefix(key)
      [
        self.class.name,
        body_cache_key_id || "",
        key.to_s,
        "v#{BODY_CACHE_VERSION}",
      ].reject(&:blank?).join(":")
    end

    # Internal: return a unique cache key id for this user content body
    def body_cache_key_id
      if respond_to?(:new_record?) && respond_to?(:id) && !new_record?
        id
      elsif respond_to?(:sha)
        sha
      end
    end

    def body_version
      Digest::SHA256.hexdigest(body.to_s)
    end
  end
end
