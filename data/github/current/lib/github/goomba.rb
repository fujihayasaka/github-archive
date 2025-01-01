# typed: true
# frozen_string_literal: true

require "action_view"
require "action_controller"
require "goomba"

require "github/goomba/filter"
require "github/goomba/node_filter"
require "github/goomba/input_filter"
require "github/goomba/output_filter"
require "github/goomba/async_output_filter"
require "github/goomba/async"
require "github/goomba/reference"

require "github/goomba/warp_pipe"
require "github/goomba/warp_pipe_stats"

require "github/goomba/issue_mention_filter"
require "github/goomba/project_mention_filter"
require "github/goomba/text_filter"
require "github/goomba/task_list_filter"

require "github/goomba/advisory_mention_filter"
require "github/goomba/alert_mention_filter"
require "github/goomba/animated_image_filter"
require "github/goomba/autolink_filter"
require "github/goomba/actions_annotation_autolink_filter"
require "github/goomba/azure_boards_links_filter"
require "github/goomba/pre_tag_input_filter"
require "github/goomba/camo_filter"
require "github/goomba/close_keyword_filter"
require "github/goomba/code_rendering_service_filter"
require "github/goomba/code_scanning_message_link_filter"
require "github/goomba/code_scanning_message_filter"
require "github/goomba/colon_emoji_filter"
require "github/goomba/color_filter"
require "github/goomba/commit_mention_filter"
require "github/goomba/custom_key_link_filter"
require "github/goomba/cve_mention_filter"
require "github/goomba/dependabot_alert_mention_filter"
require "github/goomba/diff_hunk_link_filter"
require "github/goomba/downcase_name_filter"
require "github/goomba/duplicate_keyword_filter"
require "github/goomba/email_commit_mention_filter"
require "github/goomba/email_issue_mention_filter"
require "github/goomba/email_mention_filter"
require "github/goomba/email_reply_filter"
require "github/goomba/email_team_mention_filter"
require "github/goomba/empty_anchor_filter"
require "github/goomba/extract_wiki_codeblocks_filter"
require "github/goomba/extract_wiki_links_filter"
require "github/goomba/extract_wiki_links_node_filter"
require "github/goomba/experiment"
require "github/goomba/filter_when_language"
require "github/goomba/filter_when_not_language"
require "github/goomba/first_paragraph_filter"
require "github/goomba/footnote_anchor_filter"
require "github/goomba/footnote_section_filter"
require "github/goomba/github_reference_filter"
require "github/goomba/group_reference_filter"
require "github/goomba/h1_filter"
require "github/goomba/https_filter"
require "github/goomba/image_alt_text_filter"
require "github/goomba/image_max_width_filter"
require "github/goomba/image_style_filter"
require "github/goomba/issue_blob_filter"
require "github/goomba/issue_dashboard_mention_filter"
require "github/goomba/label_tag_filter"
require "github/goomba/lightweight_task_list_filter"
require "github/goomba/lightweight_suggested_change_filter"
require "github/goomba/link_emphasis_filter"
require "github/goomba/markdown_element_class_filter"
require "github/goomba/markdown_filter"
require "github/goomba/markdown_alert_filter"
require "github/goomba/markup_filter"
require "github/goomba/math_block_filter"
require "github/goomba/math_display_filter"
require "github/goomba/math_inline_filter"
require "github/goomba/math_inline_backtick_filter"
require "github/goomba/mention_filter"
require "github/goomba/models_table_of_contents_filter"
require "github/goomba/models_token_button_filter"
require "github/goomba/models_markdown_body_filter"
require "github/goomba/models_rate_limit_link_filter"
require "github/goomba/models_going_beyond_rate_limits_filter"
require "github/goomba/no_referrer_filter"
require "github/goomba/no_translation_filter"
require "github/goomba/nokogiri_compatibility_filter"
require "github/goomba/orphan_href_filter"
require "github/goomba/plain_text_input_filter"
require "github/goomba/platform_raw_image_filter"
require "github/goomba/process_wiki_codeblocks_filter"
require "github/goomba/process_wiki_links_filter"
require "github/goomba/raw_image_filter"
require "github/goomba/rel_nofollow_filter"
require "github/goomba/remove_ansi_colors_filter"
require "github/goomba/remove_non_suggested_change_filter"
require "github/goomba/relative_link_filter"
require "github/goomba/repo_zip_image_filter"
require "github/goomba/sanitization_filter"
require "github/goomba/sanitizer"
require "github/goomba/secure_assets_url_filter"
require "github/goomba/set_table_role_filter"
require "github/goomba/snippet_clipboard_copy_filter"
require "github/goomba/strip_image_filter"
require "github/goomba/strip_link_filter"
require "github/goomba/suggested_change_filter"
require "github/goomba/syntax_highlight_filter"
require "github/goomba/table_of_contents_filter"
require "github/goomba/team_mention_filter"
require "github/goomba/textile_filter"
require "github/goomba/text_direction_filter"
require "github/goomba/title_markdown_filter"
require "github/goomba/ui_schema_filter"
require "github/goomba/unescape_text_links_input_filter"
require "github/goomba/unicode_emoji_filter"
require "github/goomba/user_error_filter"
require "github/goomba/utf8_filter"
require "github/goomba/backslash_escape_filter"
require "github/goomba/video_tag_filter"
require "github/goomba/wiki_markup_filter"
require "github/goomba/wiki_relative_image_filter"
require "github/goomba/wiki_relative_link_filter"
require "github/goomba/wiki_class_name_filter"
require "github/goomba/yaml_filter"
require "github/goomba/picture_filter"
require "github/goomba/media_wiki_toc_prefix_filter"
require "github/goomba/tabbable_table_filter"


module GitHub
  module Goomba
    NAME_PREFIX = "user-content-"

    context = {
      asset_root: "#{GitHub.asset_host_url}/images/icons",
      base_url: GitHub.url,
      http_url: "http://#{GitHub.host_name}", # for the HttpsFilter
      name_prefix: NAME_PREFIX,
    }
    context[:flags] = Rinku::AUTOLINK_SHORT_DOMAINS if GitHub.enterprise?

    markup_sanitizer = Sanitizer.from_allowlist(GitHub::HTML::MARKUP_ALLOWLIST)
    markup_sanitizer_with_img_style = Sanitizer.from_allowlist(GitHub::HTML::MARKUP_ALLOWLIST_WITH_IMG_STYLE)
    markdown_sanitizer = Sanitizer.from_allowlist(GitHub::HTML::ALLOWLIST)
    markdown_sanitizer_with_video = Sanitizer.from_allowlist(GitHub::HTML::WITH_VIDEO)
    markdown_sanitizer_with_video_and_img_style = Sanitizer.from_allowlist(GitHub::HTML::WITH_VIDEO_AND_IMG_STYLE)
    code_scanning_message_sanitizer = Sanitizer.from_allowlist(
      ::HTML::Pipeline::SanitizationFilter::ALLOWLIST.merge({
        elements: %w[a br],
        attributes: { "a" => ["href"] },
      }),
    )
    code_scanning_markdown_message_sanitizer = Sanitizer.from_allowlist(
      ::HTML::Pipeline::SanitizationFilter::ALLOWLIST.merge({
        elements: %w[a br ul li],
        attributes: { "a" => ["href"] },
      }),
    )
    code_scanning_status_message_sanitizer = Sanitizer.from_allowlist(
      ::HTML::Pipeline::SanitizationFilter::ALLOWLIST.merge({
        elements: %w[a br ul li p code pre details summary],
        attributes: { "a" => ["href"] },
      }),
    )

    highlighted_search_results_allowlist = Sanitizer.from_allowlist(
      ::HTML::Pipeline::SanitizationFilter::ALLOWLIST.merge({
        elements: %w[a br ul li em tt],
        attributes: {
          # There are a number of input filters that got moved from the old html-pipeline that
          # need their attributes allowed through the sanitizer. Ideally we'd remove these
          # once these filters are converted to node filters.
          "a" => %w(href class data-error-text data-id data-permission-text data-url data-hovercard-url data-hovercard-type data-octo-click data-octo-dimensions),
        },
        protocols: {
          # + keeps the string from being frozen
          "a" => { "href" => ::HTML::Pipeline::SanitizationFilter::ANCHOR_SCHEMES + [+"ftp"] }
        }
      }))

    # Folks seem to be adding `a` tags as text, not as anchors in their memex columns
    # Because of this, we dont want to include memex in the list of sanitizers below,
    # which have require_any_attributes set.
    memex_item_value_sanitizer = Sanitizer.from_allowlist(
      GitHub::HTML::ALLOWLIST.merge({
        elements: %w(a g-emoji),
      })
    )

    wiki_pipeline_sanitizer = Sanitizer.from_allowlist(GitHub::HTML::WikiSanitizationFilter.new("").allowlist)

    [
      markup_sanitizer,
      markdown_sanitizer,
      markdown_sanitizer_with_video,
      markdown_sanitizer_with_video_and_img_style,
      code_scanning_message_sanitizer,
      code_scanning_markdown_message_sanitizer,
      code_scanning_status_message_sanitizer,
      wiki_pipeline_sanitizer
    ].each do |s|
      s.require_any_attributes(:a, "href", "id", "name")
      s.name_prefix = NAME_PREFIX
      s.limit_nesting :sup, 2
      s.limit_nesting :sub, 2
      s.limit_nesting :ul, 10
      s.limit_nesting :ol, 10
    end

    # A pipeline used to process git blob objects via the markup filter,
    # sanitization, and image hijacking. No mentions or related features are
    # used.
    #
    # Used for readmes and blob previews.
    MarkupPipeline = WarpPipe.new(
      input_filters: [
        UTF8Filter,
        YamlFilter,
        MarkupFilter,
        PreTagInputFilter,
        AutolinkFilter,
      ],
      sanitizer: markdown_sanitizer_with_video_and_img_style,
      node_filters: [
        TabbableTableFilter,
        MarkdownAlertFilter,
        FilterWhenLanguage.new("Markdown", TaskListFilter),
        FilterWhenLanguage.new("Wikitext", MediaWikiTocPrefixFilter),
        DowncaseNameFilter,
        # TableOfContentsFilter will replace/update h1-h6 elements. Any filters that target elements which can be
        # descendants of elements allowing inline math (e.g. ImageStyleFilter targeting imgs inside headers) should come after
        # this filter
        TableOfContentsFilter,
        # Math filters will replace/update elements defined in MathBaseFilter::INLINE_MATH_ALLOWED_TAGS. Any filters that
        # target elements which can be descendants of elements allowing inline math (e.g. ImageStyleFilter targeting imgs inside headers)
        # should come after this filter
        MathInlineBacktickFilter,
        MathBlockFilter,
        MathDisplayFilter,
        MathInlineFilter,
        # end math filters
        ImageStyleFilter, # Must come after TableOfContentsFilter to effect images in headers
        CodeRenderingServiceFilter,
        UISchemaFilter, # Must be before CamoFilter
        SecureAssetsURLFilter, # Must be before CamoFilter
        Async::SecureAssetsPreSignFilter, # Must be before CamoFilter
        Async::GHESSecureLegacyAssetsPresignFilter, # Must be before CamoFilter
        AnimatedImageFilter, # Must be before CamoFilter and after Secure Assets Filters
        RelativeLinkFilter, # Must be before CamoFilter
        CamoFilter,
        SyntaxHighlightFilter,
        SnippetClipboardCopyFilter, # Must be after SyntaxHighlightFilter
        ColonEmojiFilter, # Must be after RelativeLinkFilter
        UnicodeEmojiFilter, # Must be after RelativeLinkFilter
        RawImageFilter, # Must be after RelativeLinkFilter
        ImageMaxWidthFilter, # Must be after RawImageFilter
        PictureFilter,
        OrphanHrefFilter,
        RelNofollowFilter,
        IssueMentionFilter,
        IssueBlobFilter,
        LabelTagFilter,
        VideoTagFilter,
        FootnoteSectionFilter,
        FootnoteAnchorFilter,
        TextDirectionFilter,
      ].compact,
      output_filters: [
        GithubReferenceFilter,
        UserErrorFilter,
      ],
      default_context: context.merge(
        skip_short_issue_reference: true,
      ),
      stats_key: "MarkupPipeline",
    )

    # Pipeline used for most types of user provided content like comments (including on Gists),
    # discussions, and issue bodies. Performs sanitization, image hijacking, and various
    # mention links.
    MarkdownPipeline = WarpPipe.new(
      input_filters: [
        UTF8Filter,
        DiffHunkLinkFilter,
        MarkdownFilter,
      ],
      sanitizer: markdown_sanitizer_with_video,
      node_filters: [
        TabbableTableFilter,
        MarkdownAlertFilter,
        DowncaseNameFilter,
        # Math filters will replace/update elements defined in MathBaseFilter::INLINE_MATH_ALLOWED_TAGS. Any filters that
        # target elements which can be descendants of elements allowing inline math (e.g. ImageStyleFilter targeting imgs inside headers)
        # should come after this filter
        MathInlineBacktickFilter,
        MathBlockFilter,
        MathDisplayFilter,
        MathInlineFilter,
        # end math filters
        TaskListFilter,
        # CloseKeywordFilter must go before other text filters but after TaskListFilter. It goes
        # early in the list because it needs access to sibling elements, but it must go after
        # TaskListFilter because that one needs ancestry access which is lost if the
        # CloseKeywordFilter finds any matching keywords.
        CloseKeywordFilter,
        CodeRenderingServiceFilter,
        UISchemaFilter, # Must be before CamoFilter
        SecureAssetsURLFilter, # Must be before CamoFilter
        Async::SecureAssetsPreSignFilter, # Must be before CamoFilter
        Async::GHESSecureLegacyAssetsPresignFilter, # Must be before CamoFilter
        AnimatedImageFilter, # Must be before CamoFilter and after Secure Assets Filters
        CamoFilter,
        ImageMaxWidthFilter,
        PictureFilter,
        (GitHub.ssl? ? HttpsFilter : nil),
        SuggestedChangeFilter,
        MentionFilter,
        TeamMentionFilter,
        IssueBlobFilter,
        IssueDashboardMentionFilter,
        CustomKeyLinkFilter,
        AlertMentionFilter,
        AdvisoryMentionFilter,
        DependabotAlertMentionFilter,
        IssueMentionFilter,
        ProjectMentionFilter,
        CommitMentionFilter,
        SetTableRoleFilter,
        CVEMentionFilter,
        DuplicateKeywordFilter,
        ColonEmojiFilter,
        UnicodeEmojiFilter,
        SyntaxHighlightFilter,
        SnippetClipboardCopyFilter, # Must be after SyntaxHighlightFilter
        MarkdownElementClassFilter,
        ColorFilter,
        RelNofollowFilter,
        VideoTagFilter,
        FootnoteSectionFilter,
        FootnoteAnchorFilter,
        TextDirectionFilter,
        LabelTagFilter,
        NoTranslationFilter,
        AzureBoardsLinksFilter,
        RepoZipImageFilter,
      ].compact,
      output_filters: [
        GithubReferenceFilter,
      ],
      post_cache_node_filters: [],
      default_context: context.merge(
        gfm: true,
      ),
      result_class: GitHub::HTML::Result,
      stats_key: "MarkdownPipeline",
    )

    # Pipeline used to format messages associated with code scanning alerts
    # In particular, placeholder links of the form [foo](<index>) are replaced
    # with real links to the related location referred to by the <index>
    #
    CodeScanningMessagePipeline = WarpPipe.new(
      input_filters: [
        UTF8Filter,
        BackslashEscapeFilter,
        CodeScanningMessageFilter,
      ],
      sanitizer: code_scanning_message_sanitizer,
      node_filters: [
        (GitHub.ssl? ? HttpsFilter : nil),
        RelNofollowFilter,
        CodeScanningMessageLinkFilter,
      ].compact,
      default_context: context.merge(gfm: true),
      result_class: GitHub::HTML::Result,
      stats_key: "CodeScanningMessagePipeline",
    )

    # Same as the CodeScanningMessagePipeline but for markdown messages with lists in.
    #
    CodeScanningMarkdownPipeline = WarpPipe.new(
      input_filters: [
        UTF8Filter,
        MarkdownFilter,
      ],
      sanitizer: code_scanning_markdown_message_sanitizer,
      node_filters: [
        (GitHub.ssl? ? HttpsFilter : nil),
        RelNofollowFilter,
        MarkdownElementClassFilter,
        CodeScanningMessageLinkFilter,
      ].compact,
      default_context: context.merge(gfm: true, add_markdown_element_classes: true),
      result_class: GitHub::HTML::Result,
      stats_key: "CodeScanningMarkdownPipeline",
    )

    # Pipeline used to format messages associated with code scanning status messages.
    # Mostly used for including links in status messages, but may be extended in the future.
    CodeScanningStatusMessagePipeline = WarpPipe.new(
      input_filters: [
        UTF8Filter,
        BackslashEscapeFilter,
        CodeScanningMessageFilter,
      ],
      sanitizer: code_scanning_status_message_sanitizer,
      node_filters: [
        (GitHub.ssl? ? HttpsFilter : nil),
        RelNofollowFilter,
        MarkdownElementClassFilter,
      ].compact,
      default_context: context.merge(gfm: true, add_markdown_element_classes: true),
      result_class: GitHub::HTML::Result,
      stats_key: "CodeScanningStatusMessagePipeline",
    )

    # Markdown pipeline that doesn't create any new links or modify existing
    # ones.
    NonLinkingMarkdownPipeline = WarpPipe.new(
      input_filters: [
        UTF8Filter,
        MarkdownFilter,
      ],
      sanitizer: markdown_sanitizer,
      node_filters: [
        TaskListFilter,
        ImageMaxWidthFilter,
        PictureFilter,
        ColonEmojiFilter,
        UnicodeEmojiFilter,
        SyntaxHighlightFilter,
        SnippetClipboardCopyFilter, # Must be after SyntaxHighlightFilter
        MarkdownElementClassFilter,
      ].compact,
      default_context: context.merge(gfm: true),
      result_class: GitHub::HTML::Result,
      stats_key: "NonLinkingMarkdownPipeline",
    )

    # Markdown pipeline that is used solely to find task items.
    # Is used to render progress bar in issue/PR timeline
    LightweightTaskListPipeline = WarpPipe.new(
      input_filters: [
        UTF8Filter,
        MarkdownFilter,
      ],
      sanitizer: markdown_sanitizer,
      node_filters: [
        LightweightTaskListFilter
      ].compact,
      default_context: context.merge(gfm: true),
      result_class: GitHub::HTML::Result,
      stats_key: "LightweightTaskListPipeline",
    )

    # Markdown pipeline that is used solely to abstract out code suggestions in PR comments.
    PRCommentSuggestionPipeline = WarpPipe.new(
      input_filters: [
        MarkdownFilter,
      ],
      sanitizer: markdown_sanitizer,
      node_filters: [
        LightweightSuggestedChangeFilter,
        RemoveNonSuggestedChangeFilter,
      ].compact,
      stats_key: "PRCommentSuggestionPipeline",
    )

    # Pipeline used for the embedded readmes/descriptions of
    # package registry packages.
    PackageVersionPipeline = WarpPipe.new(
      input_filters: [
        UTF8Filter,
        MarkdownFilter,
      ],
      sanitizer: markdown_sanitizer,
      node_filters: [
        DowncaseNameFilter,
        TaskListFilter,

        # CloseKeywordFilter must go before other text filters but after TaskListFilter. It goes
        # early in the list because it needs access to sibling elements, but it must go after
        # TaskListFilter because that one needs ancestry access which is lost if the
        # CloseKeywordFilter finds any matching keywords.
        CloseKeywordFilter,
        CamoFilter,
        ImageMaxWidthFilter,
        PictureFilter,
        # TableOfContentsFilter will replace/update h1-h6 elements. Any filters that target elements which can be
        # descendants of elements allowing inline math (e.g. ImageStyleFilter targeting imgs inside headers) should come after
        # this filter
        TableOfContentsFilter,
        (GitHub.ssl? ? HttpsFilter : nil),
        SuggestedChangeFilter,
        MentionFilter,
        TeamMentionFilter,
        IssueBlobFilter,
        IssueMentionFilter,
        CommitMentionFilter,
        AdvisoryMentionFilter,
        CVEMentionFilter,
        DuplicateKeywordFilter,
        ColonEmojiFilter,
        UnicodeEmojiFilter,
        SyntaxHighlightFilter,
        SnippetClipboardCopyFilter, # Must be after SyntaxHighlightFilter
        MarkdownElementClassFilter,
        ColorFilter,
        RelNofollowFilter,
      ].compact,
      output_filters: [
        GithubReferenceFilter,
      ],
      default_context: context.merge(
        gfm: true,
      ),
      result_class: GitHub::HTML::Result,
      stats_key: "PackageVersionPipeline",
    )

    TopicDescriptionPipeline = WarpPipe.new(
      input_filters: [
        UTF8Filter,
        MarkdownFilter,
      ],
      sanitizer: markdown_sanitizer,
      node_filters: [
        ColonEmojiFilter,
        UnicodeEmojiFilter,
        StripImageFilter,
        RelNofollowFilter,
      ].compact,
      default_context: context.merge(gfm: true),
      result_class: GitHub::HTML::Result,
      stats_key: "TopicDescriptionPipeline",
    )

    ReleasePipeline = WarpPipe.new(
      input_filters: [
        UTF8Filter,
        MarkdownFilter,
      ],
      sanitizer: markdown_sanitizer_with_video,
      node_filters: [
        MarkdownAlertFilter,
        TaskListFilter,
        # Math filters will replace/update elements defined in MathBaseFilter::INLINE_MATH_ALLOWED_TAGS. Any filters that
        # target elements which can be descendants of elements allowing inline math (e.g. ImageStyleFilter targeting imgs inside headers)
        # should come after this filter
        MathInlineBacktickFilter,
        MathBlockFilter,
        MathDisplayFilter,
        MathInlineFilter,
        Async::SecureAssetsPreSignFilter, # Must be before CamoFilter
        Async::GHESSecureLegacyAssetsPresignFilter, # Must be before CamoFilter
        CamoFilter,
        RelativeLinkFilter,
        RawImageFilter,
        ImageMaxWidthFilter,
        PictureFilter,
        (GitHub.ssl? ? HttpsFilter : nil),
        MentionFilter,
        TeamMentionFilter,
        CustomKeyLinkFilter,
        AdvisoryMentionFilter,
        IssueMentionFilter,
        CommitMentionFilter,
        CVEMentionFilter,
        ColonEmojiFilter,
        UnicodeEmojiFilter,
        SyntaxHighlightFilter,
        SnippetClipboardCopyFilter, # Must be after SyntaxHighlightFilter
        MarkdownElementClassFilter,
        RelNofollowFilter,
        VideoTagFilter,
        LabelTagFilter,
      ].compact,
      output_filters: [
        GithubReferenceFilter,
      ],
      default_context: context.merge(
        gfm: true,
      ),
      result_class: GitHub::HTML::Result,
      stats_key: "ReleasePipeline",
    )


    CardPipeline = WarpPipe.new(
      input_filters: [
        UTF8Filter,
        MarkdownFilter,
      ],
      sanitizer: markdown_sanitizer,
      node_filters: [
        TaskListFilter,
        # Math filters will replace/update elements defined in MathBaseFilter::INLINE_MATH_ALLOWED_TAGS. Any filters that
        # target elements which can be descendants of elements allowing inline math (e.g. ImageStyleFilter targeting imgs inside headers)
        # should come after this filter
        MathInlineBacktickFilter,
        MathBlockFilter,
        MathDisplayFilter,
        MathInlineFilter,
        CamoFilter,
        ImageMaxWidthFilter,
        PictureFilter,
        (GitHub.ssl? ? HttpsFilter : nil),
        MentionFilter,
        TeamMentionFilter,
        AdvisoryMentionFilter,
        IssueMentionFilter,
        CommitMentionFilter,
        CVEMentionFilter,
        ColonEmojiFilter,
        UnicodeEmojiFilter,
        SyntaxHighlightFilter,
        SnippetClipboardCopyFilter, # Must be after SyntaxHighlightFilter
        RelNofollowFilter,
      ].compact,
      output_filters: [
        GithubReferenceFilter,
      ],
      default_context: context.merge(gfm: true),
      result_class: GitHub::HTML::Result,
      stats_key: "CardPipeline"
    )

    # pipeline used for readmes and blob previews in graphql queries
    PlatformMarkupPipeline = WarpPipe.new(
      input_filters: [
        UTF8Filter,
        YamlFilter,
        MarkupFilter,
        AutolinkFilter,
      ],
      sanitizer: markup_sanitizer_with_img_style,
      node_filters: [
        MarkdownAlertFilter,
        FilterWhenLanguage.new("Markdown", TaskListFilter),
        DowncaseNameFilter,
        # TableOfContentsFilter will replace/update h1-h6 elements. Any filters that target elements which can be
        # descendants of elements allowing inline math (e.g. ImageStyleFilter targeting imgs inside headers) should come after
        # this filter
        TableOfContentsFilter,
        ImageStyleFilter, # Must come after TableOfContentsFilter to effect images in headers
        CamoFilter,
        SyntaxHighlightFilter,
        SnippetClipboardCopyFilter, # Must be after SyntaxHighlightFilter
        RelativeLinkFilter,
        ColonEmojiFilter, # Must be after RelativeLinkFilter
        UnicodeEmojiFilter, # Must be after RelativeLinkFilter
        PlatformRawImageFilter, # Must be after RelativeLinkFilter
        ImageMaxWidthFilter, # Must be after RawImageFilter
        PictureFilter,
        OrphanHrefFilter,
        RelNofollowFilter,
      ],
      default_context: context,
      stats_key: "PlatformMarkupPipeline",
    )

    # Pipeline used for linkless descriptions.
    SimpleDescriptionPipeline = WarpPipe.new(
      input_filters: [
        UTF8Filter,
        PlainTextInputFilter,
      ],
      node_filters: [
        ColonEmojiFilter,
        UnicodeEmojiFilter,
      ],
      default_context: context,
      stats_key: "SimpleDescriptionPipeline",
    )

    PlainUserStatusPipeline = WarpPipe.new(
      input_filters: [
        UTF8Filter,
        PlainTextInputFilter,
      ],
      node_filters: [
        ColonEmojiFilter,
        UnicodeEmojiFilter,
      ],
      default_context: context,
      stats_key: "PlainUserStatusPipeline",
    )

    ProfileBioPipeline = WarpPipe.new(
      input_filters: [
        UTF8Filter,
        PlainTextInputFilter,
      ],
      node_filters: [
        ColonEmojiFilter,
        UnicodeEmojiFilter,
        MentionFilter,
        TeamMentionFilter,
      ],
      output_filters: [
        GithubReferenceFilter,
      ],
      default_context: context,
      stats_key: "ProfileBioPipeline",
    )

    ProfileCompanyPipeline = WarpPipe.new(
      input_filters: [
        UTF8Filter,
        PlainTextInputFilter,
      ],
      node_filters: [
        MentionFilter,
      ],
      output_filters: [
        GithubReferenceFilter,
      ],
      default_context: context,
      stats_key: "ProfileCompanyPipeline",
    )

    # Pipeline used for Integration Directory long-form content.
    IntegrationListingPipeline = WarpPipe.new(
      input_filters: [
        UTF8Filter,
        MarkdownFilter,
      ],
      sanitizer: markdown_sanitizer,
      node_filters: [
        CamoFilter,
        ImageMaxWidthFilter,
        PictureFilter,
        ColonEmojiFilter,
        UnicodeEmojiFilter,
      ].compact,
      default_context: context,
      result_class: GitHub::HTML::Result,
      stats_key: "IntegrationListingPipeline",
    )

    CommitSubjectPipeline = WarpPipe.new(
      input_filters: [
        UTF8Filter,
        PlainTextInputFilter,
      ],
      node_filters: [
        # CloseKeywordFilter must go first since it potentially needs to be able to look at sibling
        # elements which are lost when parsing a document fragment resulting from a replacement
        # in a previous filter.
        CloseKeywordFilter,

        MentionFilter,
        TeamMentionFilter,
        CommitMentionFilter,
        AdvisoryMentionFilter,
        CVEMentionFilter,
        ColonEmojiFilter,
        UnicodeEmojiFilter,
        RelNofollowFilter,
      ],
      output_filters: [
        GithubReferenceFilter,
      ],
      default_context: context,
      result_class: GitHub::HTML::Result,
      stats_key: "CommitSubjectPipeline",
    )

    CommitMessagePipeline = WarpPipe.new(
      input_filters: [
        UTF8Filter,
        PlainTextInputFilter,
        AutolinkFilter,
      ],
      node_filters: [
        # CloseKeywordFilter must go first since it potentially needs to be able to look at sibling
        # elements which are lost when parsing a document fragment resulting from a replacement
        # in a previous filter.
        CloseKeywordFilter,

        MentionFilter,
        TeamMentionFilter,
        CustomKeyLinkFilter,
        AdvisoryMentionFilter,
        IssueMentionFilter,
        CommitMentionFilter,
        CVEMentionFilter,
        ColonEmojiFilter,
        UnicodeEmojiFilter,
        RelNofollowFilter,
      ],
      output_filters: [
        GithubReferenceFilter,
      ],
      default_context: context,
      result_class: GitHub::HTML::Result,
      stats_key: "CommitMessagePipeline",
    )

    LongCommitMessagePipeline = WarpPipe.new(
      input_filters: [
        UTF8Filter,
        PlainTextInputFilter,
      ],
      result_class: GitHub::HTML::Result,
      stats_key: "LongCommitMessagePipeline",
    )

    # Pipeline used for the SponsorsListing long-form content.
    SponsorsListingPipeline = WarpPipe.new(
      input_filters: [
        UTF8Filter,
        MarkdownFilter,
      ],
      sanitizer: markdown_sanitizer,
      node_filters: [
        MarkdownAlertFilter,
        CamoFilter,
        ColonEmojiFilter,
        UnicodeEmojiFilter,
        H1Filter,
      ].compact,
      default_context: context,
      result_class: GitHub::HTML::Result,
      stats_key: "SponsorsListingPipeline",
    )

    # Pipeline used for SponsorsTier descriptions.
    SponsorsTierDescriptionPipeline = WarpPipe.new(
      input_filters: [
        UTF8Filter,
        MarkdownFilter,
      ],
      sanitizer: markdown_sanitizer,
      node_filters: [
        TaskListFilter,
        StripImageFilter,
        ColonEmojiFilter,
        UnicodeEmojiFilter,
        H1Filter,
      ].compact,
      default_context: context,
      result_class: GitHub::HTML::Result,
      stats_key: "SponsorsTierDescriptionPipeline",
    )

    # Pipeline used for the Marketplace long-form content.
    MarketplaceListingPipeline = WarpPipe.new(
      input_filters: [
        UTF8Filter,
        MarkdownFilter,
      ],
      sanitizer: markdown_sanitizer,
      node_filters: [
        CamoFilter,
        StripImageFilter,
        ColonEmojiFilter,
        UnicodeEmojiFilter,
        H1Filter,
      ].compact,
      default_context: context,
      result_class: GitHub::HTML::Result,
      stats_key: "MarketplaceListingPipeline",
    )

    # Pipeline to add noreferrer to 'a' tags
    # Used to avoid the referer field leaking the private token on atom feed
    NoReferrerPipeline = WarpPipe.new(
      node_filters: [
        NoReferrerFilter,
      ],
      default_context: context,
      stats_key: "NoReferrerPipeline",
    )

    # Pipeline for Git Guides on /git-guides/
    GuidesMarkdownPipeline = WarpPipe.new(
      input_filters: [
        UTF8Filter,
        MarkdownFilter,
      ],
      sanitizer: markdown_sanitizer,
      node_filters: [
        # TableOfContentsFilter will replace/update h1-h6 elements. Any filters that target elements which can be
        # descendants of elements allowing inline math (e.g. ImageStyleFilter targeting imgs inside headers) should come after
        # this filter
        TableOfContentsFilter,
        SyntaxHighlightFilter,
        SnippetClipboardCopyFilter, # Must be after SyntaxHighlightFilter
      ].compact,
      default_context: context.merge(gfm: true),
      result_class: GitHub::HTML::Result,
      stats_key: "GuidesMarkdownPipeline",
      default_cache_settings: { use_cache: true, cache_prefix: "site_guides_pipeline" },
    )

    # Pipeline for GitHub models at /marketplace/models
    ModelsMarkdownPipeline = WarpPipe.new(
      input_filters: [
        UTF8Filter,
        MarkdownFilter,
      ],
      sanitizer: markdown_sanitizer,
      node_filters: [
        ModelsTableOfContentsFilter, # Must be before TableOfContentsFilter
        TableOfContentsFilter,
        SyntaxHighlightFilter,
        SnippetClipboardCopyFilter, # Must be after SyntaxHighlightFilter
        ModelsTokenButtonFilter,
        ModelsRateLimitLinkFilter,
        ModelsGoingBeyondRateLimitsFilter,
      ].compact,
      post_cache_node_filters: [
        Async::SnippetClipboardCopyFilter,
      ],
      output_filters: [
        ModelsMarkdownBodyFilter,
      ],
      default_context: context.merge(
        gfm: true,
        force_show_snippet_buttons: true,
        use_primer_clipboard_copy: true,
        azure_link: GitHub.azure_ai_github_url
      ),
      result_class: GitHub::HTML::Result,
      stats_key: "ModelsMarkdownPipeline",
      default_cache_settings: {
        use_cache: true,
        cache_prefix: "models_pipeline",
        cache_result_keys: [:toc_headers_hash, :html_safe, :rendered, :output]
      },
    )

    # Pipeline for rule help for code scanning alerts
    # Basically a relatively simple markdown pipeline which
    # also pulls out the first paragraph.
    CodeScanningRuleHelpMarkdownPipeline = WarpPipe.new(
      input_filters: [
        UTF8Filter,
        MarkdownFilter,
      ],
      sanitizer: markdown_sanitizer,
      node_filters: [
        CamoFilter,
        ImageMaxWidthFilter,
        PictureFilter,
        (GitHub.ssl? ? HttpsFilter : nil),
        IssueBlobFilter,
        SetTableRoleFilter,
        ColonEmojiFilter,
        UnicodeEmojiFilter,
        SyntaxHighlightFilter,
        SnippetClipboardCopyFilter, # Must be after SyntaxHighlightFilter
        MarkdownElementClassFilter,
        ColorFilter,
        RelNofollowFilter,
      ].compact,
      output_filters: [
        GithubReferenceFilter,
        FirstParagraphFilter,
      ],
      default_context: context.merge(gfm: true),
      result_class: GitHub::HTML::Result,
      stats_key: "CodeScanningRuleHelpMarkdownPipeline",
    )

    ConfigAsCodeErrorMessagePipeline = WarpPipe.new(
      input_filters: [
        UTF8Filter,
        MarkdownFilter,
      ],
      node_filters: [
        SyntaxHighlightFilter,
        SnippetClipboardCopyFilter, # Must be after SyntaxHighlightFilter
        MarkdownElementClassFilter,
      ],
      sanitizer: Sanitizer.from_allowlist(
        elements: %w[pre code ul li div span b i strong],
        attributes: {
          "pre" => %w[class lang],
          "div" => ["class"],
          "span" => ["class"]
        },
      ),
      default_context: context.merge(gfm: true),
      result_class: GitHub::HTML::Result,
      stats_key: "ConfigAsCodeErrorMessagePipeline",
    )

    IssueFormTemplatesErrorMessagePipeline = WarpPipe.new(
      input_filters: [
        UTF8Filter,
        MarkdownFilter,
      ],
      sanitizer: Sanitizer.from_allowlist(
        elements: ["code"],
        ),
      default_context: context.merge(gfm: true),
      result_class: GitHub::HTML::Result,
      stats_key: "IssueFormTemplatesErrorMessagePipeline",
      )

    StructuredTemplatesCheckboxLabelPipeline = WarpPipe.new(
      input_filters: [
        UTF8Filter,
        MarkdownFilter,
      ],
      sanitizer: Sanitizer.from_allowlist(
        elements: %w[code strong em a],
        attributes: { "a" => ["href"] },
        ),
      default_context: context.merge(gfm: true),
      result_class: GitHub::HTML::Result,
      stats_key: "StructuredTemplatesCheckboxLabelPipeline",
      )

    # Pipeline used for Annotations in Actions. Only job is to linkify
    # valid urls for the domain provided by `GitHub.host_domain`, eg
    # github.com, github.localhost, etc. Will also attach a hovercard if
    # a user is referenced.
    ActionsAnnotationPipeline = WarpPipe.new(
      input_filters: [
        UTF8Filter,
        RemoveANSIColorsFilter,
        PlainTextInputFilter,
        ActionsAnnotationAutolinkFilter,
      ],
      node_filters: [
        RelNofollowFilter,
        MentionFilter,
      ],
      output_filters: [
        GithubReferenceFilter,
      ],
      default_context: context,
      result_class: GitHub::HTML::Result,
      stats_key: "ActionsAnnotationPipeline",
    )

    # Pipeline used for stories at /readme, which requires handling of
    # custom styles (by applying classes to elements)
    # This pipeline is used for internally reviewed markdown files,
    # and should not be used for user generated content
    SiteReadmePipeline = WarpPipe.new(
      input_filters: [
        UTF8Filter,
      ],
      sanitizer: Sanitizer.from_allowlist(
        elements: %w[div b i strong em u a pre code img ins del sup sub p ol ul li br h1 h2 h3 h4 h5 h6 hr blockquote source picture iframe aside span],
        attributes: {
          "a" => %w[href class],
          "div" => %w[class aria-labelledby tabindex],
          "img" => %w[class alt src width height loading decoding],
          "source" => %w[srcset type sizes],
          "p" => ["style"],
          "h3" => ["class"],
          "h4" => ["class"],
          "h5" => ["class"],
          "pre" => %w[class lang],
          "iframe" => %w[src width height allowfullscreen frameborder allow class title],
          "span" => ["class"],
        },
      ),
      node_filters: [
        ColonEmojiFilter,
        UnicodeEmojiFilter,
        SyntaxHighlightFilter,
        SnippetClipboardCopyFilter, # Must be after SyntaxHighlightFilter
        ColorFilter,
        VideoTagFilter,
      ].compact,
      output_filters: [
        GithubReferenceFilter,
      ],
      default_context: context.merge(gfm: true),
      result_class: GitHub::HTML::Result,
      stats_key: "SiteReadmePipeline",
      default_cache_settings: { use_cache: true, cache_prefix: "site_readme_pipeline" },
    )

    # Pipeline providing sanitization and image hijacking but no mention
    # related features. It is called in a number of views, but also, notably,
    # in app/api/markdown.rb when the mode is `markdown`.
    SimplePipeline = WarpPipe.new(
      input_filters: [
        UTF8Filter,
        EmptyAnchorFilter,
        AutolinkFilter
      ],
      sanitizer: markdown_sanitizer,
      node_filters: [
        # TableOfContentsFilter will replace/update h1-h6 elements. Any filters that target elements which can be
        # descendants of elements allowing inline math (e.g. ImageStyleFilter targeting imgs inside headers) should come after
        # this filter
        TableOfContentsFilter,
        AnimatedImageFilter, # MUST come BEFORE CamoFilter (or any filters that renames src).
        CamoFilter,
        PictureFilter,
        SyntaxHighlightFilter,
        RelativeLinkFilter,
        ColonEmojiFilter, # Must be after RelativeLinkFilter
        UnicodeEmojiFilter, # Must be after RelativeLinkFilter
        RawImageFilter, # Must be after RelativeLinkFilter
        ImageMaxWidthFilter,
        RelNofollowFilter,
      ],
      default_context: context.merge(
        gfm: true,
        allowlist: GitHub::HTML::ALLOWLIST,
      ),
      result_class: GitHub::HTML::Result,
      stats_key: "SimplePipeline",
    )

    # Pipeline used for really old comments and maybe other textile content
    # I guess.
    TextilePipeline = WarpPipe.new(
      input_filters: [
        UTF8Filter,
        TextileFilter,
      ],
      sanitizer:  markdown_sanitizer,
      default_context: context.merge(gfm: true),
      result_class: GitHub::HTML::Result,
      stats_key: "TextilePipeline",
    )

    EmailPipeline = WarpPipe.new(
      input_filters: [
        UTF8Filter,
        EmailReplyFilter,
        EmptyAnchorFilter,
        AutolinkFilter,
        EmailIssueMentionFilter,
        EmailMentionFilter,
        EmailCommitMentionFilter,
        EmailTeamMentionFilter,
      ],
      node_filters: [
        ColonEmojiFilter,
        UnicodeEmojiFilter,
      ],
      sanitizer: Sanitizer.from_allowlist(GitHub::HTML::MARKUP_ALLOWLIST.merge({
        elements: %w(a div span tt),
        attributes: {
          "a" => %w(href class data-error-text data-id data-permission-text data-url data-hovercard-url data-hovercard-type data-octo-click data-octo-dimensions),
          "div" => %w(class style),
          "span" => %w(class style),
        },
      })),
      default_context: context.merge({
        gfm: true,
        hide_quoted_email_addresses: true,
        disable_hovercard_attributes: true
      }),
      result_class: GitHub::HTML::Result,
      stats_key: "EmailPipeline",
    )

    DescriptionPipeline = WarpPipe.new(
      input_filters: [
        UTF8Filter,
        PlainTextInputFilter,
        EmailMentionFilter,
        EmailTeamMentionFilter,
        EmailCommitMentionFilter,
        EmailIssueMentionFilter,
        AutolinkFilter,
      ],
      node_filters: [
        ColonEmojiFilter,
        UnicodeEmojiFilter,
        RelNofollowFilter,
      ],
      sanitizer: Sanitizer.from_allowlist(GitHub::HTML::MARKUP_ALLOWLIST.merge({
        attributes: {
          "a" => %w(href class data-error-text data-id data-permission-text data-url data-hovercard-url data-hovercard-type data-octo-click data-octo-dimensions),
          "div" => %w(class),
          "span" => %w(class),
        },
      })),
      default_context: context.merge(gfm: true, link_attr: 'class="Link--inTextBlock"'),
      result_class: GitHub::HTML::Result,
      stats_key: "DescriptionPipeline",
      default_cache_settings: { use_cache: true, cache_prefix: "description_pipeline" },
    )

    EnterpriseAnnouncementPipeline = WarpPipe.new(
      input_filters: [
        UTF8Filter,
        MarkdownFilter,
      ],
      sanitizer: markdown_sanitizer_with_video,
      node_filters: [
        MarkdownAlertFilter,
        (GitHub.ssl? ? HttpsFilter : nil),
        StripImageFilter,
        MentionFilter,
        TeamMentionFilter,
        IssueBlobFilter,
        IssueMentionFilter,
        CommitMentionFilter,
        ColonEmojiFilter,
        UnicodeEmojiFilter,
        MarkdownElementClassFilter,
        ColorFilter,
        RelNofollowFilter,
        TextDirectionFilter,
        NoTranslationFilter,
      ].compact,
      output_filters: [
        GithubReferenceFilter,
      ],
      default_context: context.merge(gfm: true),
      result_class: GitHub::HTML::Result,
      stats_key: "EnterpriseAnnouncementPipeline",
    )

    HighlightedSearchResultPipeline = WarpPipe.new(
      input_filters: [
        UTF8Filter,
        UnescapeTextLinksInputFilter,
        LinkEmphasisFilter,
        EmailMentionFilter,
        EmailTeamMentionFilter,
        EmailCommitMentionFilter,
        EmailIssueMentionFilter,
        AutolinkFilter,
      ],
      node_filters: [
        ColonEmojiFilter,
        UnicodeEmojiFilter,
        RelNofollowFilter,
      ],
      sanitizer: highlighted_search_results_allowlist,
      default_context: context.merge(autolink: true),
      result_class: GitHub::HTML::Result,
      stats_key: "HighlightedSearchResultPipeline")

    WikiPipeline = WarpPipe.new(
      sanitizer: wiki_pipeline_sanitizer,
      input_filters: [
        UTF8Filter,
        ExtractWikiCodeBlocksFilter, # Must come before WikiMarkupFilter
        FilterWhenNotLanguage.new("Markdown", ExtractWikiLinksFilter), # Must come before WikiMarkupFilter
        WikiMarkupFilter,
        FilterWhenLanguage.new("Markdown", ExtractWikiLinksNodeFilter),
        ProcessWikiCodeBlocksFilter,
        ProcessWikiLinksFilter,
        WikiClassNameFilter
      ],
      node_filters: [
        MarkdownAlertFilter,
        DowncaseNameFilter,
        FilterWhenLanguage.new("Wikitext", MediaWikiTocPrefixFilter),
        # TableOfContentsFilter will replace/update h1-h6 elements. Any filters that target elements which can be
        # descendants of elements allowing inline math (e.g. ImageStyleFilter targeting imgs inside headers) should come after
        # this filter
        TableOfContentsFilter,
        # Math filters will replace/update elements defined in MathBaseFilter::INLINE_MATH_ALLOWED_TAGS. Any filters that
        # target elements which can be descendants of elements allowing inline math (e.g. ImageStyleFilter targeting imgs inside headers)
        # should come after this filter
        MathInlineBacktickFilter,
        MathBlockFilter,
        MathDisplayFilter,
        MathInlineFilter,
        CodeRenderingServiceFilter,
        WikiRelativeLinkFilter,
        SyntaxHighlightFilter,
        SnippetClipboardCopyFilter, # Must be after SyntaxHighlightFilter
        FilterWhenLanguage.new("Markdown", TaskListFilter),
        AnimatedImageFilter, # MUST come BEFORE CamoFilter (or any filters that renames src).
        RawImageFilter,
        PictureFilter,
        WikiRelativeImageFilter,
        ColonEmojiFilter,
        UnicodeEmojiFilter, # Must be after TaskListFilter
        SecureAssetsURLFilter,
        Async::SecureAssetsPreSignFilter, # Must be before CamoFilter
        Async::GHESSecureLegacyAssetsPresignFilter, # Must be before CamoFilter
        CamoFilter,
        SetTableRoleFilter,
        RelNofollowFilter,
        VideoTagFilter,
      ],
      output_filters: [
        GithubReferenceFilter,
      ],
      post_cache_node_filters: [
        Async::SnippetClipboardCopyFilter,
      ],
      default_context: context,
      result_class: GitHub::HTML::Result,
      stats_key: "WikiPipeline",
    )

    memex_item_value_sanitizer.name_prefix = NAME_PREFIX
    memex_item_value_sanitizer.disallow_attribute(:a, "target")
    MemexTextColumnPipeline = WarpPipe.new(
      input_filters: [
        UTF8Filter,
        SanitizationFilter,
        AutolinkFilter
      ],
      node_filters: [
        ColonEmojiFilter,
        UnicodeEmojiFilter,
      ],
      sanitizer: memex_item_value_sanitizer,
      default_context: context,
      result_class: GitHub::HTML::Result,
      stats_key: "MemexTextColumnPipeline",
    )

    # Pipeline used to format user provided comment in the actions deployment protection log UI.
    # We don't want image or video shown in this comment box
    ActionsDeploymentProtectionLogPipeline = WarpPipe.new(
      input_filters: [
        UTF8Filter,
        MarkdownFilter,
      ],
      sanitizer: markdown_sanitizer,
      node_filters: [
        ColonEmojiFilter,
        UnicodeEmojiFilter,
        StripImageFilter,
        RelNofollowFilter,
        TextDirectionFilter,
      ],
      default_context: context,
      result_class: GitHub::HTML::Result,
      stats_key: "ActionsDeploymentProtectionLogPipeline",
      default_cache_settings: { use_cache: true, cache_prefix: "actions_deployment_protection_log" },
    )

    # Pipeline used for the enterprise "README" content.
    BusinessLongDescriptionPipeline = WarpPipe.new(
      input_filters: [
        UTF8Filter,
        MarkdownFilter,
      ],
      sanitizer: markdown_sanitizer,
      node_filters: [
        CamoFilter,
        ColonEmojiFilter,
        UnicodeEmojiFilter,
        MentionFilter,
      ],
      output_filters: [
        GithubReferenceFilter,
      ],
      default_context: context,
      result_class: GitHub::HTML::Result,
      stats_key: "BusinessLongDescriptionPipeline",
    )

    # Pipeline used to turn URLs into links for failed merge condition reasons
    PullRequestMergeConditionMessagePipeline = WarpPipe.new(
      input_filters: [
        UTF8Filter,
        PlainTextInputFilter,
        AutolinkFilter,
      ],
      sanitizer: markdown_sanitizer,
      result_class: GitHub::HTML::Result,
      stats_key: "PullRequestMergeConditionMessagePipeline",
    )

  end
end
