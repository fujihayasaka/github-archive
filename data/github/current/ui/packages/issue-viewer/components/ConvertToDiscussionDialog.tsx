import {Banner, Dialog} from '@primer/react/experimental'
import {useRelayEnvironment, graphql, useFragment, useLazyLoadQuery} from 'react-relay'
import {Suspense, useCallback, useId, useMemo, useState} from 'react'
import {commitConvertIssueToDiscussionMutation} from '../mutations/convert-issue-to-discussion-mutation'
import type {ConvertIssueToDiscussionInput} from '../mutations/__generated__/convertIssueToDiscussionMutation.graphql'
import {BUTTON_LABELS} from '../constants/buttons'
import {LABELS} from '../constants/labels'
import {VALUES} from '../constants/values'
// eslint-disable-next-line no-restricted-imports
import {reportError} from '@github-ui/failbot'
import {CheckIcon, XIcon} from '@primer/octicons-react'
import {DiscussionCategoryPickerInternal} from '@github-ui/item-picker/DiscussionCategoryPicker'
import {testIdProps} from '@github-ui/test-id-props'
import type {ConvertToDiscussionDialogIssuePropertiesFragment$key} from './__generated__/ConvertToDiscussionDialogIssuePropertiesFragment.graphql'
import {IssuesLoadingSkeleton} from '@github-ui/issues-loading-skeleton'
import type {
  ConvertToDiscussionDialogQuery,
  ConvertToDiscussionDialogQuery$data,
} from './__generated__/ConvertToDiscussionDialogQuery.graphql'
import styles from './ConvertToDiscussionDialog.module.css'
import {FormControl} from '@primer/react'

export type ConvertToDiscussionDialogProps = {
  issueId: string
  owner: string
  repository: string
  onClose: () => void
}

export const IssuePropertiesFragment = graphql`
  fragment ConvertToDiscussionDialogIssuePropertiesFragment on Issue {
    comments {
      totalCount
    }
    reactions {
      totalCount
    }
    tasklistBlocks {
      totalCount
    }
    assignees {
      totalCount
    }
    projectsV2 {
      totalCount
    }
    milestone {
      __typename
    }
  }
`

export const ConvertToDiscussionDialog = (props: ConvertToDiscussionDialogProps) => {
  const data = useLazyLoadQuery<ConvertToDiscussionDialogQuery>(
    graphql`
      query ConvertToDiscussionDialogQuery($issueId: ID!, $first: Int!) {
        node(id: $issueId) {
          ... on Issue {
            ...ConvertToDiscussionDialogIssuePropertiesFragment @dangerously_unaliased_fixme
            repository {
              ...DiscussionCategoryPickerDiscussionCategories
            }
          }
        }
      }
    `,
    {
      first: VALUES.convertToDiscussionCategoriesFirst,
      issueId: props.issueId,
    },
  )

  return <ConvertToDiscussionDialogInternal {...props} data={data} />
}

export type ConvertToDiscussionDialogPropsInternal = ConvertToDiscussionDialogProps & {
  data: ConvertToDiscussionDialogQuery$data
}
export const ConvertToDiscussionDialogInternal = ({data, issueId, onClose}: ConvertToDiscussionDialogPropsInternal) => {
  const [selectedCategoryId, setSelectedCategoryId] = useState<string>()
  const [isConverting, setIsConverting] = useState(false)
  const [showError, setShowError] = useState(false)
  const environment = useRelayEnvironment()

  const issueProperties = data?.node
  const repository = issueProperties?.repository

  const handleConvertToDiscussion = useCallback(() => {
    if (!selectedCategoryId || isConverting) return
    setIsConverting(true)

    const input: ConvertIssueToDiscussionInput = {
      categoryId: selectedCategoryId,
      issueId,
    }

    commitConvertIssueToDiscussionMutation({
      environment,
      input,
      onError: (e: Error) => {
        reportError(formatError(e.message))
        setShowError(true)
        setIsConverting(false)
      },
      onCompleted: response => {
        if (response.convertIssueToDiscussion?.discussion) {
          const discussion = response.convertIssueToDiscussion?.discussion
          // eslint-disable-next-line react-hooks/react-compiler
          window.location.href = discussion.url
          return
        } else {
          for (const e of response.convertIssueToDiscussion?.errors || []) {
            reportError(formatError(e.message))
          }
          setShowError(true)
          setIsConverting(false)
        }
      },
    })
  }, [environment, isConverting, issueId, selectedCategoryId])

  const categoryId = useId()

  return (
    <Dialog
      title={LABELS.convertToDiscussion.title}
      onClose={onClose}
      footerButtons={[
        {content: BUTTON_LABELS.cancel, onClick: onClose, disabled: isConverting},
        {
          content: BUTTON_LABELS.acknowledgeAndConvertToDiscussion,
          buttonType: 'danger',
          onClick: handleConvertToDiscussion,
          disabled: !selectedCategoryId || isConverting,
          loading: isConverting,
          ...testIdProps('convertButton'),
        },
      ]}
      width="large"
      renderBody={({children}) => {
        return (
          <div className="p-3">
            {showError && (
              <Banner
                title="Convert issue failed"
                hideTitle
                description={LABELS.somethingWentWrong}
                variant="critical"
                className="mb-2"
              />
            )}
            {children}
          </div>
        )
      }}
    >
      <Suspense fallback={<DialogLoadingSkeleton />}>
        {issueProperties && <WhatHappens issueProperties={issueProperties} />}
        <FormControl>
          <FormControl.Label htmlFor={categoryId}>{LABELS.convertToDiscussion.selectCategoryTitle}</FormControl.Label>
          {repository && (
            <DiscussionCategoryPickerInternal
              categoryId={categoryId}
              onSelect={setSelectedCategoryId}
              discussionCategoriesData={repository}
            />
          )}
        </FormControl>
      </Suspense>
    </Dialog>
  )
}

function formatError(message: string) {
  return new Error(LABELS.convertToDiscussion.error(message))
}

const DialogLoadingSkeleton = () => (
  <>
    <div className={styles.firstLoader}>
      <IssuesLoadingSkeleton height="sm" width="80%" />
    </div>
    <div className={styles.container}>
      <div className={styles.commonLoader}>
        <IssuesLoadingSkeleton height="sm" width="50%" />
      </div>
      <div className={styles.commonLoader}>
        <IssuesLoadingSkeleton height="sm" width="90%" />
      </div>
      <div className={styles.commonLoader}>
        <IssuesLoadingSkeleton height="sm" width="87%" />
      </div>
    </div>
    <div className={styles.commonLoader}>
      <IssuesLoadingSkeleton height="dm" width="50%" />
    </div>
    <div className={styles.commonLoader}>
      <IssuesLoadingSkeleton height="dm" width="100%" />
    </div>
  </>
)

type WhatHappensProps = {
  issueProperties: ConvertToDiscussionDialogIssuePropertiesFragment$key
}
const WhatHappens = ({issueProperties}: WhatHappensProps) => {
  const issue = useFragment(IssuePropertiesFragment, issueProperties)
  const {comments, reactions, tasklistBlocks, assignees, projectsV2, milestone} = issue

  const affirmations = useMemo(() => {
    const results = [
      LABELS.convertToDiscussion.affirmations.closedAndLocked,
      LABELS.convertToDiscussion.affirmations.same,
    ]

    if (comments.totalCount > 0 || reactions.totalCount > 0) {
      results.push(LABELS.convertToDiscussion.affirmations.commentsAndReactions)
    }

    return results
  }, [comments, reactions])

  const warnings = useMemo(() => {
    const results = []

    if ((tasklistBlocks?.totalCount || 0) > 0) {
      results.push(LABELS.convertToDiscussion.warnings.taskListBlocks)
    }

    if (assignees.totalCount > 0) {
      results.push(LABELS.convertToDiscussion.warnings.assignees)
    }

    if (projectsV2.totalCount > 0) {
      results.push(LABELS.convertToDiscussion.warnings.projects)
    }

    if (milestone) {
      results.push(LABELS.convertToDiscussion.warnings.milestone)
    }

    return results
  }, [tasklistBlocks, assignees, projectsV2, milestone])

  return (
    <>
      <p className="mb-3">{LABELS.convertToDiscussion.whatHappens}</p>

      <ul className="list-style-none ml-3 mb-3">
        {affirmations.map((text, index) => (
          // eslint-disable-next-line @eslint-react/no-array-index-key
          <Result key={index} success text={text} />
        ))}
        {warnings.map((text, index) => (
          // eslint-disable-next-line @eslint-react/no-array-index-key
          <Result key={index} success={false} text={text} />
        ))}
      </ul>
    </>
  )
}

type ResultProps = {
  success: boolean
  text: string
}
const Result = ({success, text}: ResultProps) => {
  return (
    <li className="mb-1">
      {success ? <CheckIcon className="fgColor-success mr-1" /> : <XIcon className="fgColor-danger mr-1" />}
      {text}
    </li>
  )
}
