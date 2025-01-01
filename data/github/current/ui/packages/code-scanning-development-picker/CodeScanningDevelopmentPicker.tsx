import {useCallback, useEffect, useState} from 'react'
import {LazyPullRequestAndBranchPicker} from '@github-ui/item-picker/PullRequestAndBranchPicker'
import {
  type PropsWithPartialAnchor,
  type ReactPartialAnchorProps,
  useExternalAnchor,
} from '@github-ui/react-core/react-partial-anchor'
import {GearIcon} from '@primer/octicons-react'
import {Button, Heading} from '@primer/react'
import {relayEnvironmentWithMissingFieldHandlerForNode} from '@github-ui/relay-environment'
import {RelayEnvironmentProvider} from 'react-relay'
import {clsx} from 'clsx'
import styles from './CodeScanningDevelopmentPicker.module.css'
import type {PullRequestPickerPullRequest$data} from '@github-ui/item-picker/PullRequestPickerPullRequest.graphql'
import type {BranchPickerRef$data} from '@github-ui/item-picker/BranchPickerRef.graphql'
import {pickerItemToLinkPayload, useUpdateAlertLinksMutation} from './hooks/use-update-alert-links-mutation'

type CodeScanningDevelopmentPickerSharedProps = {
  repositoryNwo: string
  repositoryId: number
  alertNumber: number
  linkedPullRequests: PullRequestPickerPullRequest$data[]
  linkedBranches: BranchPickerRef$data[]
  isCreateBranchDialogOpen: boolean
  updateAlertLinksPath: string
  triggerOpen?: boolean
  onBranchesChange?: (branches: string[]) => void
  onPullRequestsChange?: (pullRequests: number[]) => void
}

type CodeScanningDevelopmentPickerInternalProps = CodeScanningDevelopmentPickerSharedProps & {
  open: boolean
  setOpen: (open: boolean) => void
}

export type CodeScanningDevelopmentPickerProps = CodeScanningDevelopmentPickerSharedProps & ReactPartialAnchorProps

export function CodeScanningDevelopmentPicker(props: CodeScanningDevelopmentPickerProps) {
  const [open, setOpen] = useState(false)

  if (props?.reactPartialAnchor) {
    return <ExternallyAnchoredCodeScanningDevelopmentPicker {...props} reactPartialAnchor={props.reactPartialAnchor} />
  }

  return <CodeScanningDevelopmentPickerInternal open={open} setOpen={setOpen} {...props} />
}

function ExternallyAnchoredCodeScanningDevelopmentPicker(
  props: PropsWithPartialAnchor<CodeScanningDevelopmentPickerSharedProps>,
) {
  const {ref: extAnchor, open, setOpen} = useExternalAnchor(props.reactPartialAnchor)

  useEffect(() => {
    extAnchor.current?.setAttribute('hidden', 'true')
  }, [extAnchor])

  return <CodeScanningDevelopmentPickerInternal open={open} setOpen={setOpen} {...props} />
}

function CodeScanningDevelopmentPickerInternal(props: CodeScanningDevelopmentPickerInternalProps) {
  const anchorElement = (anchorProps: React.HTMLAttributes<HTMLElement>) => {
    return (
      <Button
        className={clsx('mb-2', 'color-bg-transparent', 'p-0', styles.Button)}
        data-testid="internal-anchor"
        block
        trailingAction={GearIcon}
        variant="invisible"
        aria-label="Open development menu"
        {...anchorProps}
      >
        <Heading as="h3" className="h6 color-fg-muted">
          Development
        </Heading>
      </Button>
    )
  }

  const mutation = useUpdateAlertLinksMutation(props.updateAlertLinksPath)

  const onSelectionChange = useCallback(
    (selection: Array<PullRequestPickerPullRequest$data | BranchPickerRef$data>) => {
      const initialSelection = [...props.linkedPullRequests, ...props.linkedBranches]

      const toDelete = initialSelection.flatMap(x => (selection.includes(x) ? [] : [pickerItemToLinkPayload(x)]))
      const toCreate = selection.flatMap(x => (initialSelection.includes(x) ? [] : [pickerItemToLinkPayload(x)]))

      if (toDelete.length === 0 && toCreate.length === 0) {
        return
      }

      mutation.mutate(
        {
          linksToCreate: toCreate,
          linksToDelete: toDelete,
        },
        {
          onSuccess: data => {
            const prLinks = data.currentLinks.flatMap(link => (link.pullRequestNumber ? [link.pullRequestNumber] : []))
            const branchLinks = data.currentLinks.flatMap(link => (link.pullRequestNumber ? [] : [link.refName]))
            props.onPullRequestsChange?.(prLinks)
            props.onBranchesChange?.(branchLinks)
          },
        },
      )
    },
    [props, mutation],
  )

  return (
    <RelayEnvironmentProvider environment={relayEnvironmentWithMissingFieldHandlerForNode()}>
      <LazyPullRequestAndBranchPicker
        repoNameWithOwner={props.repositoryNwo}
        initialSelectedBranches={props.linkedBranches}
        initialSelectedPrs={props.linkedPullRequests}
        onSelectionChange={onSelectionChange}
        title={'Link a branch or pull request'}
        anchorElement={anchorElement}
        shortcutsEnabled={false}
        triggerOpen={props.open}
        onOpen={() => props.setOpen(true)}
        onClose={() => props.setOpen(false)}
        preventClose={props.isCreateBranchDialogOpen}
        loading={false} // we may need to do sth more complex with the loading
      />
    </RelayEnvironmentProvider>
  )
}
