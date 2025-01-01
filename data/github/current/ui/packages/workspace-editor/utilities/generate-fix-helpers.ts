import type {CopilotChatMessageStreamer} from '@github-ui/copilot-chat/utils/copilot-chat-message-streamer'
import type {Repository} from '@github-ui/current-repository'
import {blobPath} from '@github-ui/paths'

import {assertDefined} from './asserts'
import type {BlobPayload, FocusedGenerativeTaskData} from './workspace-editor-types'

/**
 * Generated fix info returned by the agent after it was able to successfully generate a fix.
 */
export interface GeneratedFixReference {
  data: {
    description: string
    git_patch: string
    target_file_commit_oid: string
    target_file_path: string
  }
  type: 'github.code-reviser.result'
}

export interface CommentClassificationReference {
  data: {
    actionable: boolean
    reasoning: string
    impact: string
  }
  type: 'github.classify.result'
}

/**
 * Full response object from the code reviser agent.
 */
export interface AgentResponse {
  copilot_references: GeneratedFixReference[] | CommentClassificationReference[]
  type: undefined
}

/**
 * The generated fix returned by the agent, as a friendly typescript object.
 */
export interface GeneratedFix {
  description: string
  gitPatch: string
  targetFileCommitOid: string
  targetFilePath: string
  commentsVersion: string
}

export interface CommentClassification {
  actionable: boolean
  reasoning: string
  commentsVersion: string
}

/**
 * Generates a key used to store the generated fix in local storage.
 */
export function generatedFixKey(
  repoOwner: string,
  repoName: string,
  pullRequestNumber: string,
  generatedFixId: string,
  suffix?: string,
) {
  return `hadron-generated-fix/${repoOwner}/${repoName}/${pullRequestNumber}/${generatedFixId}${
    suffix ? `/${suffix}` : ''
  }`
}

export type GenerateFixVariables = {blob: BlobPayload}

/**
 * Takes a response from the agent and extracts the generated fix from it, while validating that the expected fields
 * are present.
 *
 * @param agentResponse Streamed response from the agent
 * @returns parsed generated fix object
 */
export function validateAndExtractGeneratedFix(agentResponse: AgentResponse): GeneratedFix {
  const generatedFixReference = (agentResponse?.copilot_references?.[0] as GeneratedFixReference)?.data
  assertDefined(generatedFixReference, 'No generated fix reference found in agent response')
  assertDefined(generatedFixReference.description, 'No description found in generated fix reference')
  assertDefined(generatedFixReference.git_patch, 'No git patch found in generated fix reference')
  assertDefined(
    generatedFixReference.target_file_commit_oid,
    'No target file commit oid found in generated fix reference',
  )
  assertDefined(generatedFixReference.target_file_path, 'No target file path found in generated fix reference')

  return {
    description: generatedFixReference.description,
    gitPatch: generatedFixReference.git_patch,
    targetFileCommitOid: generatedFixReference.target_file_commit_oid,
    targetFilePath: generatedFixReference.target_file_path,
    commentsVersion: '',
  }
}

/**
 * Takes a response from the agent and extracts the classification from it, while validating that the expected fields
 * are present.
 *
 * @param agentResponse Streamed response from the agent
 * @returns parsed generated fix object
 */
export function validateAndExtractCommentClassification(agentResponse: AgentResponse): CommentClassification {
  const commentClassificationResp = (agentResponse?.copilot_references?.[0] as CommentClassificationReference)?.data
  assertDefined(commentClassificationResp, 'No comment classification reference found in agent response')
  assertDefined(
    commentClassificationResp.actionable,
    'No actionable decision found in comment classification reference',
  )
  assertDefined(commentClassificationResp.reasoning, 'No reasoning found in comment classification reference')

  return {
    actionable: commentClassificationResp.actionable,
    reasoning: commentClassificationResp.reasoning,
    commentsVersion: '',
  }
}

/**
 * Simple helper function that reads the contents of the stream and returns the first message (code reviser agent
 * only returns one currently).
 */
export async function handleStreamingMessage(
  streamer: CopilotChatMessageStreamer<AgentResponse>,
): Promise<AgentResponse> {
  const messages: AgentResponse[] = []
  for await (const message of streamer.stream()) {
    messages.push(message)
  }

  if (messages.length === 0) {
    throw new Error('No messages received from stream')
  }

  if (messages.length > 1) {
    throw new Error('More than one message received from stream')
  }

  const message = messages[0]!
  return message
}

export function buildCommentsPayload(generatedFixTask: FocusedGenerativeTaskData) {
  const comments = [generatedFixTask.comment, ...generatedFixTask.replies]
  return comments.map(comment => ({
    type: 'github.pull-request-comment',
    data: {
      type: 'pull-request-comment',
      body: comment.bodyText,
      commit_id: comment.commitOid,
      created_at: comment.createdAt,
      updated_at: comment.updatedAt,
      diff_hunk: comment.diffHunk,
      id: comment.id,
      in_reply_to_id: comment.inReplyToId,
      line: comment.lineNumber,
      original_commit_id: comment.originalCommitOid,
      original_line: comment.originalLineNumber,
      original_start_line: comment.originalStartLineNumber,
      pull_request_id: comment.pullRequestId,
      side: comment.side,
      start_line: comment.startLineNumber,
      start_side: comment.startSide,
      subject_type: comment.subjectType,
    },
  }))
}

export function buildFilePayload(blob: BlobPayload, repo: Pick<Repository, 'id' | 'name' | 'ownerLogin'>) {
  const filePath = blobPath({commitish: blob.refName, filePath: blob.path, repo: repo.name, owner: repo.ownerLogin})
  const fileUrl = new URL(filePath, window.location.origin).toString()

  return {
    type: 'github.file',
    data: {
      type: 'file',
      commitOID: blob.commitOid,
      content: blob.blobContents,
      languageID: blob.languageId,
      languageName: blob.languageName,
      path: blob.path,
      ref: `refs/heads/${blob.refName}`,
      repoID: repo.id,
      repoName: repo.name,
      repoOwner: repo.ownerLogin,
      url: fileUrl,
    },
  }
}
