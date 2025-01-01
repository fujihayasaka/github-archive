# typed: true
# frozen_string_literal: true

module GitHub::Goomba::Async
  autoload :NodeFilter, "github/goomba/async/node_filter"
  autoload :MentionFilter, "github/goomba/async/mention_filter"
  autoload :TeamMentionFilter, "github/goomba/async/team_mention_filter"
  autoload :CommitMentionFilter, "github/goomba/async/commit_mention_filter"
  autoload :TasklistBlockFilter, "github/goomba/async/tasklist_block_filter"
  autoload :TrackingBlockFilter, "github/goomba/async/tracking_block_filter"
  autoload :CompareMentionFilter, "github/goomba/async/compare_mention_filter"
  autoload :CloseKeywordFilter, "github/goomba/async/close_keyword_filter"
  autoload :IssueMentionFilter, "github/goomba/async/issue_mention_filter"
  autoload :RichIssueMentionFilter, "github/goomba/async/rich_issue_mention_filter"
  autoload :ProjectMentionFilter, "github/goomba/async/project_mention_filter"
  autoload :IssueBlobFilter, "github/goomba/async/issue_blob_filter"
  autoload :LabelTagFilter, "github/goomba/async/label_tag_filter"
  autoload :AdvisoryMentionFilter, "github/goomba/async/advisory_mention_filter"
  autoload :CVEMentionFilter, "github/goomba/async/cve_mention_filter"
  autoload :VideoTagFilter, "github/goomba/async/video_tag_filter"
  autoload :SnippetClipboardCopyFilter, "github/goomba/async/snippet_clipboard_copy_filter"
  autoload :AlertMentionFilter, "github/goomba/async/alert_mention_filter"
  autoload :DependabotAlertMentionFilter, "github/goomba/async/dependabot_alert_mention_filter"
  autoload :SecureAssetsPreSignFilter, "github/goomba/async/secure_assets_presign_filter"
  autoload :TasklistBlockItemFilter, "github/goomba/async/tasklist_block_item_filter"
  autoload :GHESSecureLegacyAssetsPresignFilter, "github/goomba/async/ghes_secure_legacy_assets_presign_filter"
end
