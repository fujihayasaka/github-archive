import {CopyToClipboardButton} from '@github-ui/copy-to-clipboard/Button'
import {ErrorBoundary} from '@github-ui/react-core/error-boundary'
import {AlertIcon} from '@primer/octicons-react'
import {Dialog, Heading, Link, SegmentedControl, TextInput} from '@primer/react'
import {Blankslate} from '@primer/react/experimental'
import {clsx} from 'clsx'
import {useState} from 'react'
import {useSetDefaultProtocol} from '../../../../hooks/mutations/use-set-default-protocol-mutation'
import {useMergeInstructionsPageData} from '../../../../page-data/loaders/use-merge-instructions-page-data'
import type {PullRequestMergeConditionResult} from '../../../../types'
import styles from './CommandLineInstructionsDialog.module.css'

export type CommandLineInstructionsDialogProps = {
  baseRefName: string
  conflictsCondition: {result: PullRequestMergeConditionResult} | undefined
  headRepository: {ownerLogin: string; name: string} | null
  isCrossRepo: boolean
  onClose: () => void
  returnFocusRef: React.RefObject<HTMLElement> | undefined
}

/**
 * The outer command line instructions dialog, which contains an error boundary
 */
export default function CommandLineInstructionsDialog(props: CommandLineInstructionsDialogProps) {
  const fallback = (
    <Dialog
      width="xlarge"
      height="auto"
      role="dialog"
      onClose={props.onClose}
      returnFocusRef={props.returnFocusRef}
      title="Merging via command line"
    >
      <Blankslate>
        <Blankslate.Visual>
          <AlertIcon size={24} className="fgColor-muted mt-3 mb-3" />
        </Blankslate.Visual>
        <Blankslate.Heading>
          <strong>Unable to load the merge instructions</strong>
        </Blankslate.Heading>
        <div className="mb-n2">
          <Blankslate.Description>
            Try refreshing the page or if the problem persists{' '}
            <a className="fgColor-muted" href="https://support.github.com/">
              <u>contact support</u>{' '}
            </a>
          </Blankslate.Description>
        </div>
      </Blankslate>
    </Dialog>
  )

  return (
    <ErrorBoundary fallback={fallback}>
      <CommandLineInstructionsDialogInner {...props} />
    </ErrorBoundary>
  )
}

/**
 * The inner command line instructions dialog, which fetches data
 * Exists so that the `CommandLineInstructionsDialog` can manage its own error state
 */
function CommandLineInstructionsDialogInner({
  baseRefName,
  conflictsCondition,
  headRepository,
  isCrossRepo,
  onClose,
  returnFocusRef,
}: CommandLineInstructionsDialogProps) {
  const {
    data: {
      crossRepoPatchUrl,
      patchUrl,
      pushProtocols,
      resolvingMergeConflictsDocsUrl,
      shellEscapingDocsUrl,
      shellSafeBaseRefName,
      shellSafeCrossRepoHeadRefName,
      shellSafeHeadRefName,
      shellSafeNamesIncludePlaceholders,
    },
  } = useMergeInstructionsPageData(baseRefName)

  const defaultProtocolFromApi = pushProtocols.find(p => p.isAvailable && p.isDefault)
  const initialProtocolType = headRepository ? defaultProtocolFromApi?.protocol ?? 'PATCH' : 'PATCH'
  const [selectedProtocolType, setSelectedProtocolType] = useState<'HTTP' | 'SSH' | 'PATCH'>(initialProtocolType)
  const hasConflicts = conflictsCondition?.result === 'FAILED'
  const selectedProtocol = pushProtocols.find(p => p.protocol === selectedProtocolType)

  const httpProtocol = pushProtocols.find(p => p.protocol === 'HTTP')
  const sshProtocol = pushProtocols.find(p => p.protocol === 'SSH')

  const sshIsAvailable = (headRepository && sshProtocol?.isAvailable) ?? false
  const httpsIsAvailable = (headRepository && httpProtocol?.isAvailable) ?? false

  const {mutate: setProtocolFromUrl} = useSetDefaultProtocol(baseRefName)

  function getCloneUrl() {
    if (selectedProtocolType === 'PATCH') {
      return isCrossRepo ? crossRepoPatchUrl : patchUrl
    } else {
      return selectedProtocol?.url ?? patchUrl
    }
  }

  const setPersistableProtocol = (protocol: 'HTTP' | 'SSH') => {
    setSelectedProtocolType(protocol)
    const apiURL = pushProtocols.find(p => p.protocol === protocol)?.stickyUrl
    if (apiURL) {
      setProtocolFromUrl(apiURL)
    }
  }

  const cloneUrl = getCloneUrl()

  return (
    <Dialog
      width="xlarge"
      height="auto"
      role="dialog"
      onClose={onClose}
      returnFocusRef={returnFocusRef}
      renderHeader={({dialogDescriptionId, dialogLabelId}) => (
        <Dialog.Header id={dialogLabelId} className={styles.header}>
          <div className="d-flex">
            <div className="d-flex flex-column px-2 py-1 flex-grow-1">
              <Dialog.Title>{hasConflicts ? 'Checkout via the command line' : 'Merging via command line'}</Dialog.Title>
              <Dialog.Subtitle id={dialogDescriptionId}>
                If you do not want to use the merge button or an automatic merge cannot be performed, you can perform a
                manual merge on the command line. However, the following steps are not applicable if the base branch is
                protected.
                {shellSafeNamesIncludePlaceholders && (
                  <>
                    {' '}
                    <Link href={shellEscapingDocsUrl}>
                      Learn about dealing with special characters on the command line.
                    </Link>
                  </>
                )}
              </Dialog.Subtitle>
            </div>
            <Dialog.CloseButton onClose={onClose} />
          </div>
        </Dialog.Header>
      )}
    >
      <Heading as="h3" className="h5 pb-1">
        URL
      </Heading>
      <div className="d-flex flex-items-center gap-2">
        <SegmentedControl aria-label="Select merge option">
          {httpsIsAvailable && (
            <SegmentedControl.Button
              selected={'HTTP' === selectedProtocolType}
              onClick={() => setPersistableProtocol('HTTP')}
            >
              HTTPS
            </SegmentedControl.Button>
          )}
          {sshIsAvailable && (
            <SegmentedControl.Button
              selected={'SSH' === selectedProtocolType}
              onClick={() => setPersistableProtocol('SSH')}
            >
              SSH
            </SegmentedControl.Button>
          )}
          <SegmentedControl.Button
            selected={'PATCH' === selectedProtocolType}
            onClick={() => setSelectedProtocolType('PATCH')}
          >
            Patch
          </SegmentedControl.Button>
        </SegmentedControl>
        <TextInput aria-label="Clone URL" className="flex-1 f6" monospace value={cloneUrl} readOnly />
        <CopyToClipboardButton aria-label="Copy clone URL" textToCopy={cloneUrl} />
      </div>
      <Instructions
        cloneUrl={cloneUrl}
        crossRepoPatchUrl={crossRepoPatchUrl}
        hasConflicts={hasConflicts}
        isCrossRepo={isCrossRepo}
        resolvingMergeConflictsDocsUrl={resolvingMergeConflictsDocsUrl}
        selectedProtocolType={selectedProtocolType}
        shellSafeBaseRefName={shellSafeBaseRefName}
        shellSafeCrossRepoHeadRefName={shellSafeCrossRepoHeadRefName}
        shellSafeHeadRefName={shellSafeHeadRefName}
      />
    </Dialog>
  )
}

/**
 * Renders the correct instructions based on the pull request conditions
 */
function Instructions({
  cloneUrl,
  crossRepoPatchUrl,
  hasConflicts,
  isCrossRepo,
  resolvingMergeConflictsDocsUrl,
  selectedProtocolType,
  shellSafeBaseRefName,
  shellSafeCrossRepoHeadRefName,
  shellSafeHeadRefName,
}: {
  cloneUrl: string | undefined
  crossRepoPatchUrl: string
  hasConflicts: boolean
  isCrossRepo: boolean
  resolvingMergeConflictsDocsUrl: string
  selectedProtocolType: string
  shellSafeBaseRefName: string
  shellSafeCrossRepoHeadRefName: string
  shellSafeHeadRefName: string
}) {
  switch (true) {
    case isCrossRepo:
      return (
        <CrossRepoInstructions
          cloneUrl={cloneUrl}
          crossRepoPatchUrl={crossRepoPatchUrl}
          selectedProtocolType={selectedProtocolType}
          shellSafeBaseRefName={shellSafeBaseRefName}
          shellSafeCrossRepoHeadRefName={shellSafeCrossRepoHeadRefName}
          shellSafeHeadRefName={shellSafeHeadRefName}
        />
      )
    case hasConflicts:
      return (
        <MergeConflictsInstructions
          shellSafeBaseRefName={shellSafeBaseRefName}
          shellSafeHeadRefName={shellSafeHeadRefName}
          resolvingMergeConflictsDocsUrl={resolvingMergeConflictsDocsUrl}
        />
      )
    default:
      return (
        <StandardMergeInstructions
          shellSafeBaseRefName={shellSafeBaseRefName}
          shellSafeHeadRefName={shellSafeHeadRefName}
        />
      )
  }
}

/**
 * Cross Repo Instructions
 */
function CrossRepoInstructions({
  cloneUrl,
  crossRepoPatchUrl,
  selectedProtocolType,
  shellSafeBaseRefName,
  shellSafeCrossRepoHeadRefName,
  shellSafeHeadRefName,
}: {
  selectedProtocolType: string
  cloneUrl: string | undefined
  crossRepoPatchUrl: string
  shellSafeBaseRefName: string
  shellSafeCrossRepoHeadRefName: string
  shellSafeHeadRefName: string
}) {
  return (
    <>
      <CommandLineInstructionStep
        stepNumber={1}
        instruction="From your project repository, check out a new branch and test the changes."
        commands={[
          `git checkout -b ${shellSafeCrossRepoHeadRefName} ${shellSafeBaseRefName}`,
          selectedProtocolType === 'PATCH'
            ? `curl -L ${crossRepoPatchUrl} | git am -3`
            : `git pull ${cloneUrl} ${shellSafeHeadRefName}`,
        ]}
        copyButtonAriaLabel="Copy command"
      />
      <CommandLineInstructionStep
        stepNumber={2}
        instruction="Merge the changes and update on GitHub."
        commands={[
          `git checkout ${shellSafeBaseRefName}`,
          `git merge --no-ff ${shellSafeCrossRepoHeadRefName}`,
          `git push origin ${shellSafeBaseRefName}`,
        ]}
        copyButtonAriaLabel="Copy command"
      />
    </>
  )
}

/**
 * Merge Conflicts Instructions
 */
function MergeConflictsInstructions({
  resolvingMergeConflictsDocsUrl,
  shellSafeBaseRefName,
  shellSafeHeadRefName,
}: {
  shellSafeBaseRefName: string
  shellSafeHeadRefName: string
  resolvingMergeConflictsDocsUrl: string
}) {
  return (
    <>
      <CommandLineInstructionStep
        stepNumber={1}
        instruction="Clone the repository or update your local repository with the latest changes."
        commands={[`git pull origin ${shellSafeBaseRefName}`]}
        copyButtonAriaLabel="Copy clone command"
      />
      <CommandLineInstructionStep
        stepNumber={2}
        instruction="Switch to the head branch of the pull request."
        commands={[`git checkout ${shellSafeHeadRefName}`]}
        copyButtonAriaLabel="Copy checkout command"
      />
      <CommandLineInstructionStep
        stepNumber={3}
        instruction="Merge the base branch into the head branch."
        commands={[`git merge ${shellSafeBaseRefName}`]}
        copyButtonAriaLabel="Copy merge command"
      />
      <CommandLineInstructionStep
        stepNumber={4}
        instruction="Fix the conflicts and commit the result."
        customHelpText={
          <span>
            See <a href={resolvingMergeConflictsDocsUrl}>Resolving a merge conflict using the command line</a> for
            step-by-step instructions on resolving merge conflicts.
          </span>
        }
      />
      <CommandLineInstructionStep
        stepNumber={5}
        instruction="Push the changes."
        commands={[`git push -u origin ${shellSafeBaseRefName}`]}
        copyButtonAriaLabel="Copy push command"
      />
    </>
  )
}

/**
 *
 * Standard Merge Instructions
 */
function StandardMergeInstructions({
  shellSafeHeadRefName,
  shellSafeBaseRefName,
}: {
  shellSafeHeadRefName: string
  shellSafeBaseRefName: string
}) {
  return (
    <>
      <CommandLineInstructionStep
        stepNumber={1}
        instruction="Clone the repository or update your local repository with the latest changes."
        commands={[`git pull origin ${shellSafeBaseRefName}`]}
        copyButtonAriaLabel="Copy clone command}"
      />
      <CommandLineInstructionStep
        stepNumber={2}
        instruction="Switch to the base branch of the pull request."
        commands={[`git checkout ${shellSafeBaseRefName}`]}
        copyButtonAriaLabel="Copy checkout command"
      />
      <CommandLineInstructionStep
        stepNumber={3}
        instruction="Merge the head branch into the base branch."
        commands={[`git merge ${shellSafeHeadRefName}`]}
        copyButtonAriaLabel="Copy merge command"
      />
      <CommandLineInstructionStep
        stepNumber={4}
        instruction="Push the changes."
        commands={[`git push -u origin ${shellSafeBaseRefName}`]}
        copyButtonAriaLabel="Copy push command"
      />
    </>
  )
}

type CommandLineInstructionProps = {
  stepNumber: number
  instruction: string
  commands?: string[]
  copyButtonAriaLabel?: string
  customHelpText?: React.ReactNode
}

/**
 * Displays an instruction with step and command information
 */
function CommandLineInstructionStep({
  stepNumber,
  instruction,
  commands,
  copyButtonAriaLabel,
  customHelpText,
}: CommandLineInstructionProps) {
  return (
    <div className="mt-3">
      <p>
        <span className="text-bold">Step {stepNumber}</span> {instruction}
      </p>
      {commands && commands?.length > 0 && copyButtonAriaLabel && (
        <div className="bgColor-muted rounded-2 d-flex flex-items-center flex-justify-between mb-4">
          <p className={clsx('text-mono f6 ml-3 my-3 pb-1 flex-shrink-1', styles.commandWrapper)}>
            {commands.map(command => (
              <span className={clsx(styles.instruction, 'd-block')} key={command}>
                {command}
              </span>
            ))}
          </p>
          <CopyToClipboardButton
            className="m-3"
            aria-label={copyButtonAriaLabel}
            textToCopy={commands.join('\n')}
            iconButtonVariant="invisible"
            size="small"
          />
        </div>
      )}
      {customHelpText}
    </div>
  )
}
