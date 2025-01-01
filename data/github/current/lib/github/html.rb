# typed: false
# frozen_string_literal: true

require "active_support"
require "active_support/core_ext/object/deep_dup"
require "nokogiri"
require "html/pipeline"
require "scientist"

module GitHub
  # GitHub HTML processing filters and utilities. This module includes a small
  # framework for defining DOM based content filters and applying them to user
  # provided content.
  #
  # See GitHub::HTML::Filter for information on building filters.
  module HTML
    autoload :MathBaseFilter, "github/html/math_base_filter"
    autoload :BodyContent, "github/html/body_content"
    autoload :CamoFilter, "github/html/camo_filter"
    autoload :CommitMentionFilter, "github/html/commit_mention_filter"
    autoload :CommitPathParser, "github/html/commit_path_parser"
    autoload :Diff, "github/html/diff"
    autoload :DiscussionReference, "github/html/discussion_reference"
    autoload :EmojiFilter, "github/html/emoji_filter"
    autoload :EmptyAnchorFilter, "github/html/empty_anchor_filter"
    autoload :FilterWhenLanguage, "github/html/filter_when_language"
    autoload :FilterWhenNotLanguage, "github/html/filter_when_not_language"
    autoload :HttpsFilter, "github/html/https_filter"
    autoload :IssueMentionFilter, "github/html/issue_mention_filter"
    autoload :IssueReference, "github/html/issue_reference"
    autoload :LeadingNewlineFilter, "github/html/leading_newline_filter"
    autoload :LinkEmphasisFilter, "github/html/link_emphasis_filter"
    autoload :MarkdownFilter, "github/html/markdown_filter"
    autoload :MarkupFilter, "github/html/markup_filter"
    autoload :MathBlockFilter, "github/html/math_block_filter"
    autoload :MathDisplayFilter, "github/html/math_display_filter"
    autoload :MathInlineFilter, "github/html/math_inline_filter"
    autoload :MathInlineBacktickFilter, "github/html/math_inline_backtick_filter"
    autoload :MentionFilter, "github/html/mention_filter"
    autoload :NamePrefixFilter, "github/html/name_prefix_filter"
    autoload :Pipeline, "github/html/pipeline"
    autoload :PlainTextInputFilter, "github/html/plain_text_input_filter"
    autoload :RawImageFilter, "github/html/raw_image_filter"
    autoload :RelNofollowFilter, "github/html/rel_nofollow_filter"
    autoload :RelativeLinkFilter, "github/html/relative_link_filter"
    autoload :SanitizationFilter, "github/html/sanitization_filter"
    autoload :SecureAssetsURLFilter, "github/html/secure_assets_url_filter"
    autoload :SetTableRoleFilter, "github/html/set_table_role_filter"
    autoload :SyntaxHighlightFilter, "github/html/syntax_highlight_filter"
    autoload :TableOfContentsFilter, "github/html/table_of_contents_filter"
    autoload :TeamMentionFilter, "github/html/team_mention_filter"
    autoload :UTF8Filter, "github/html/utf8_filter"
    autoload :PictureFilter, "github/html/picture_filter"
    autoload :AnimatedImageFilter, "github/html/animated_image_filter"
    autoload :ExtractWikiCodeBlocksFilter, "github/html/extract_wiki_code_blocks_filter"
    autoload :ExtractWikiLinksFilter, "github/html/extract_wiki_links_filter"
    autoload :ExtractWikiLinksNodeFilter, "github/html/extract_wiki_links_node_filter"
    autoload :WikiMarkupFilter, "github/html/wiki_markup_filter"
    autoload :ProcessWikiLinksFilter, "github/html/process_wiki_links_filter"
    autoload :ProcessWikiCodeBlocksFilter, "github/html/process_wiki_code_blocks_filter"
    autoload :WikiSanitizationFilter, "github/html/wiki_sanitization_filter"
    autoload :CodeRenderingServiceFilter, "github/html/code_rendering_service_filter"


    Filter                = ::HTML::Pipeline::Filter
    require "github/html/filter"

    AutolinkFilter = ::HTML::Pipeline::AutolinkFilter
    ActionsAnnotationAutolinkFilter = ::HTML::Pipeline::ActionsAnnotationAutolinkFilter
    EmailReplyFilter         = ::HTML::Pipeline::EmailReplyFilter
    TextileFilter            = ::HTML::Pipeline::TextileFilter
    DocumentFragment         = ::HTML::Pipeline::DocumentFragment

    # An object for results passed back from the Pipelines
    # This allows us to have some explicit-ness around the types of things that
    # pipelines add to the repsonse.
    #
    # Members of the Result:
    #   output - the DocumentFragment or String result of the Pipeline
    #   mentioned_users - see GitHub::HTML::MentionFilter
    #   mentioned_usernames - see GitHub::HTML::MentionFilter
    #   mentioned_teams - see GitHub::HTML::TeamMentionFilter
    #   commits - see GitHub::HTML::CommitMentionFilter
    #   commits_count - see GitHub::HTML::CommitMentionFilter
    #   issues - see GitHub::HTML::IssueMentionFilter
    #   task_list_items - See TaskList::Filter
    #   tracked_issue_anchors - See TaskList::Filter
    #   tracked_alert_anchors - See TaskList::Filter && GitHub::Goomba::AlertMentionFilter
    #   toc - See TableOfContentsFilter
    #   html_safe - See GitHub::HTML::SanitizationFilter and GitHub::HTML::PlainTextInputFilter
    #   links - see GitHub::Goomba::AzureBoardsLinksFilter
    class Result
      attr_writer :task_list_items, :tracked_issue_anchors
      attr_accessor :output, :mentioned_users, :mentioned_usernames, :mentioned_teams, :commits, :commits_count, :issues, :toc, :html_safe, :discussions, :links, :tracked_alert_anchors, :tasklist_block_errors

      # Convert an HTML::Result or HTML::Result-like hash to an html string
      def self.to_html(result)
        html = if result[:output].is_a?(String)
          result[:output]
        else
          result[:output].to_html
        end

        result[:html_safe] ? html.html_safe : html # rubocop:disable Rails/OutputSafety
      end

      # Convert an HTML::Result or HTML::Result-like hash to the inner text of
      # the HTML output
      def self.to_text(result)
        html = to_html(result)

        # this is 3-4x faster than using Nokogiri!
        doc = ::Goomba::DocumentFragment.new(html)
        # Unlike `to_html`, regardless of whether the input `result` was
        # `html_safe` or not, we _do not_ mark the return value as `html_safe`.
        # The inner text of a HTML fragment is a completely different thing
        # than the the HTML fragment itself. For example, all entities within
        # HTML fragement that had been escaped for safety will be decoded
        # when we call `text_content` here and are _not_ safe.
        doc.children.map(&:text_content).join.strip
      end

      def initialize(output = nil, mentioned_users = nil, mentioned_usernames = nil,
        mentioned_teams = nil, commits = nil, commits_count = nil, issues = nil,
        task_list_items = nil, tracked_issue_anchors = nil, toc = nil, html_safe = nil,
        new_urls = nil, discussions = nil, tracked_alert_anchors = nil, links = [])
        @output              = output
        @mentioned_users     = mentioned_users
        @mentioned_usernames = mentioned_usernames
        @mentioned_teams     = mentioned_teams
        @commits             = commits
        @commits_count       = commits_count
        @new_urls            = new_urls
        @issues              = issues
        @task_list_items     = task_list_items
        @tracked_issue_anchors = tracked_issue_anchors
        @links               = links
        @toc                 = toc
        @html_safe           = html_safe
        @discussions         = discussions
        @tracked_alert_anchors = tracked_alert_anchors
      end

      def to_s
        output.to_s
      end

      def [](variable_symbol)
        instance_variable_get("@#{variable_symbol}")
      end

      def []=(variable_symbol, value)
        instance_variable_set("@#{variable_symbol}", value)
      end

      # Public: Merge a Result-like object into this Result, overwriting any matching values in this result.
      def merge!(other)
        hash = other.is_a?(Hash) ? other : other.to_h
        hash.keys.each do |key|
          self[key] = hash[key]
        end
        self
      end

      def to_h
        instance_variables.each_with_object({}) do |variable, hash|
          hash[variable.to_s.delete("@").to_sym] = instance_variable_get(variable)
        end
      end

      # Public: returns an Array of TaskList::Item objects.
      def task_list_items
        @task_list_items || []
      end

      def tracked_issue_anchors
        @tracked_issue_anchors || []
      end
    end

    def self.parse(*args)
      ::HTML::Pipeline.parse(*args)
    end

    # Filter implementations
    require "task_list"

    context = {}
    context[:flags] = Rinku::AUTOLINK_SHORT_DOMAINS if GitHub.enterprise?

    # Inherit sanitization allowlist from html-pipeline but customize it further.
    ALLOWLIST = ::HTML::Pipeline::SanitizationFilter::ALLOWLIST.deep_dup
    ALLOWLIST[:attributes].each_value do |attrs|
      # rel    - GitHub uses `rel` for things like `rel=whatever` to trigger
      #          behavior that could be unsafe with user controlled content.
      # target - `target=_blank` allows the linked to site to perform
      #          "tab nabbing" attacks by using `window.opener`.
      # vspace - messes up layout of a page and can render the page it's
      #          included on unusable.
      attrs.reject! { |attr| %w(rel target vspace).include?(attr) }
    end


    ALLOWLIST[:attributes][:all] << "id"
    ALLOWLIST[:elements] << "section"
    ALLOWLIST[:attributes]["section"] = if ALLOWLIST[:attributes]["section"].nil?
      ["data-footnotes"]
    else
      ALLOWLIST[:attributes]["section"].concat(["data-footnotes"])
    end
    ALLOWLIST[:attributes]["a"] = ALLOWLIST[:attributes]["a"].concat(%w[href data-footnote-ref data-footnote-backref])

    WITH_VIDEO = ALLOWLIST.deep_dup
    WITH_VIDEO[:elements] << "video"

    WITH_VIDEO_AND_IMG_STYLE = WITH_VIDEO.deep_dup
    WITH_VIDEO_AND_IMG_STYLE[:attributes][:all] << "data-sourcepos"
    WITH_VIDEO_AND_IMG_STYLE[:attributes][:img] = %w(style)

    email_allowlist = ALLOWLIST.merge(
      elements: %w(a div span),
      attributes: {
        "a" => %w(href),
        "div" => %w(class style),
        "span" => %w(class),
      },
    )

    limited_allowlist = ALLOWLIST.merge(
      elements: %w(b i strong em a pre code img ins del sup sub p ol ul li br h1 h2 h3 h4 h5 h6),
    )

    MARKUP_ALLOWLIST = ALLOWLIST.dup
    MARKUP_ALLOWLIST[:attributes] = ALLOWLIST[:attributes].merge(
      "table" => ALLOWLIST[:attributes].fetch("table", []) + %w(data-table-type),
      "a" => %w(href data-error-text data-id data-permission-text data-url data-hovercard-url data-hovercard-type data-octo-click data-octo-dimensions)
    )

    MARKUP_ALLOWLIST_WITH_IMG_STYLE = MARKUP_ALLOWLIST.deep_dup
    MARKUP_ALLOWLIST_WITH_IMG_STYLE[:attributes][:img] = %w(style)

    class InvalidPipelineError < StandardError; end

    # Intercepts calls to an HTML pipeline, and run a science experiment with a Goomba one
    class ExperimentalPipeline < Pipeline
      include Scientist

      def initialize(*args, experiment:, pipeline_name:, extra_context: {}, skip_experiment_in_test: false, ignored_fields: [], presumed_safe: nil, use_cache: false)
        super(*args)
        @safe_call = ::HTML::Pipeline.instance_method(:call).bind(self)
        @ignored_fields = (ignored_fields + [:toc_headers_hash]).uniq
        @experiment = experiment
        @extra_context = extra_context
        @pipeline_name = pipeline_name
        @presumed_safe = presumed_safe
        @skip_experiment_in_test = skip_experiment_in_test && Rails.env.test?
        @use_cache = use_cache
      end

      # call returns the entire result class, which some callsites expect
      def call(input, context = {})
        run_experiment(input, context)
      end

      # to_html returns only the html string output from a pipeline run
      def to_html(input, context = {}, result = nil)
        result = run_experiment(input, context)
        result[:html_safe] ? result.output.html_safe : result.output # rubocop:disable Rails/OutputSafety
      end

      private

      def run_experiment(input, context)
        context = context.merge({ pipeline_run_id: SecureRandom.hex })
        result = if @skip_experiment_in_test
          @safe_call.call(input, context)
        else
          science @experiment do |experiment|
            experiment.use do
              @safe_call.call(input.dup, context)
            end

            experiment.try do
              raise InvalidPipelineError unless GitHub::Goomba.const_defined?(@pipeline_name)
              pipeline = GitHub::Goomba.const_get(@pipeline_name)
              pipeline.call(input.dup, context.merge(@extra_context), cache_settings: { use_cache: @use_cache })
            end

            experiment.compare do |control, candidate|
              unless @presumed_safe.nil?
                control[:html_safe] = true if @presumed_safe
              end
              GitHub::Goomba::Experiment.compare_results(control, candidate, @ignored_fields)
            end

            experiment.clean do |value|
              GitHub::Goomba::Experiment.clean_result(value)
            end
          end
        end

        # the wiki pipeline never performs this operation, so we double-check the output is OK and manually
        # set this flag
        result
      end
    end

    extend self
  end
end
