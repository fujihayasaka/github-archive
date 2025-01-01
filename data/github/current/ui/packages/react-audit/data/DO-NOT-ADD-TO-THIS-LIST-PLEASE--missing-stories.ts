/* eslint @github-ui/github-monorepo/filename-convention: "off" */
/**
 * 🚨 DO NOT ADD TO THIS LIST PLEASE! 🚨
 * Writing Storybook stories makes components discoverable, promotes reusability, and provides free accessibility (axe) scanning in CI!
 * Help us build a more inclusive and maintainable library of shared components.
 * Not sure how to write a story for your component? Reach out to #react! 😊
 *
 * There are a few legitimate reasons to skip a story:
 * - Your component does not render any UI or renders only its children: for example a context provider
 * - Your module is a hook or other util that does not directly render UI that could be tested in Storybook
 *
 * We check for these in `/ui/packages/react-audit/utils.ts`. If you find a new common use case,
 * please open a PR to add it to the check. Thank you!
 */
export const MISSING_STORIES = [
  'ui/packages/ago/Ago.tsx',
  'ui/packages/code-view-shared/components/DuplicateOnKeydownButton.tsx',
  'ui/packages/commenting/components/pull-request-comment/PullRequestCommentComposer.tsx',
  'ui/packages/commit-attribution/components/AuthorAvatar.tsx',
  'ui/packages/commit-checks-status/ChecksStatusBadge.tsx',
  'ui/packages/commit-checks-status/CheckStatusDialog.tsx',
  'ui/packages/conversations/components/AddCommentEditor.tsx',
  'ui/packages/conversations/components/ConversationCommentBox.tsx',
  'ui/packages/conversations/components/ReviewThread.tsx',
  'ui/packages/conversations/components/ReviewThreadComment.tsx',
  'ui/packages/conversations/components/ReviewThreadCommentWithoutReactions.tsx',
  'ui/packages/conversations/components/StartConversation.tsx',
  'ui/packages/conversations/components/StaticUnifiedDiffPreview.tsx',
  'ui/packages/conversations/components/SuggestedChangeView.tsx',
  'ui/packages/copilot-chat/components/AgentsDialogs.tsx',
  'ui/packages/copilot-chat/components/AllTopicsButton.tsx',
  'ui/packages/copilot-chat/components/Autocomplete.tsx',
  'ui/packages/copilot-chat/components/Chat.tsx',
  'ui/packages/copilot-chat/components/ChatMessagesGroup.tsx',
  'ui/packages/copilot-chat/components/ChatPanel.tsx',
  'ui/packages/copilot-chat/components/ChatScrollContainer.tsx',
  'ui/packages/copilot-chat/components/Confirmation.tsx',
  'ui/packages/copilot-chat/components/ConversationFeedbackDialog.tsx',
  'ui/packages/copilot-chat/components/CopilotBadgeV2.tsx',
  'ui/packages/copilot-chat/components/Errors.tsx',
  'ui/packages/copilot-chat/components/Feedback.tsx',
  'ui/packages/copilot-chat/components/FigmaChatReference.tsx',
  'ui/packages/copilot-chat/components/FunctionCallBadge.tsx',
  'ui/packages/copilot-chat/components/FunctionLoadingUtils.tsx',
  'ui/packages/copilot-chat/components/KnowledgeSelectPanel.tsx',
  'ui/packages/copilot-chat/components/MentionLink.tsx',
  'ui/packages/copilot-chat/components/ModelPicker.tsx',
  'ui/packages/copilot-chat/components/PersonalInstructionsDialog.tsx',
  'ui/packages/copilot-chat/components/PreviousThreadsHeaderMenu.tsx',
  'ui/packages/copilot-chat/components/ReferencesSelectPanel.tsx',
  'ui/packages/copilot-chat/components/ReferenceToken.tsx',
  'ui/packages/copilot-chat/components/RepoAvatar.tsx',
  'ui/packages/copilot-chat/components/Service/ServiceView.tsx',
  'ui/packages/copilot-chat/components/Toolbar.tsx',
  'ui/packages/copilot-chat/components/UserMessage.tsx',
  'ui/packages/copilot-chat/components/WithAnimatedEllipsis.tsx',
  'ui/packages/copilot-chat/components/WithShimmerEffect.tsx',
  'ui/packages/copilot-chat/utils/copilot-chat-manager.tsx',
  'ui/packages/copilot-popover/CopilotPopover.tsx',
  'ui/packages/copilot-progress-indicator/CopilotProgressIndicator.tsx',
  'ui/packages/current-repository/CurrentRepository.tsx',
  'ui/packages/current-user/CurrentUser.tsx',
  'ui/packages/diff-file-header/DiffFileHeader.tsx',
  'ui/packages/diff-file-header/LinesChangedCounterLabel.tsx',
  'ui/packages/diff-lines/components/DiffLineTableCellParts.tsx',
  'ui/packages/diffs/components/HunkKebabIcon.tsx',
  'ui/packages/diffs/components/SplitDiffTable.tsx',
  'ui/packages/diffs/components/UnifiedDiffTable.tsx',
  'ui/packages/issues-bulk-actions/JobInfo.tsx',
  'ui/packages/pull-requests/App.tsx',
  'ui/packages/react-core/PrimerFeatureFlags.tsx',
  'ui/packages/repos-file-tree-view/components/ExpandFileTreeButton.tsx',
  'ui/packages/repos-file-tree-view/components/FindFilesShortcut.tsx',
  'ui/packages/repos-file-tree-view/components/ReposFileTreePane.tsx',
  // This has stories:
  // - ui/packages/safe-html/UnsafeHTMLBox.stories.tsx
  // - ui/packages/safe-html/UnsafeHTMLText.stories.tsx
  // - ui/packages/safe-html/UnsafeHTMLDiv.stories.tsx
  'ui/packages/safe-html/UnsafeHTML.tsx',
  'ui/packages/sandbox-view/SandboxView.tsx',
  'ui/packages/screen-size/ScreenSize.tsx',
]
