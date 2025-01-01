import {KebabHorizontalIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, Button, Heading, IconButton, Stack} from '@primer/react'
import styles from './ChecklistComplete.module.css'
import {Blankslate} from '@primer/react/experimental'

interface ChecklistCompleteProps {
  onDismiss?: () => void
}

export const ChecklistComplete = ({onDismiss}: ChecklistCompleteProps) => {
  return (
    <Stack direction="vertical" gap="normal" className="mb-3" data-testid="getting-started-checklist-complete">
      <Stack direction="horizontal" justify="space-between" align="center">
        <Heading id="checklist-heading" as="h2" className={styles.header}>
          Getting started
        </Heading>
        <Stack direction="horizontal" gap="condensed" align="center">
          <ActionMenu>
            <ActionMenu.Anchor>
              <IconButton
                icon={KebabHorizontalIcon}
                aria-label="Options"
                variant="invisible"
                data-testid="checklist-options"
              />
            </ActionMenu.Anchor>
            <ActionMenu.Overlay align="end">
              <ActionList>
                <ActionList.LinkItem onClick={onDismiss} data-testid="checklist-remove-option">
                  Remove from dashboard
                </ActionList.LinkItem>
              </ActionList>
            </ActionMenu.Overlay>
          </ActionMenu>
        </Stack>
      </Stack>
      <Blankslate border className={styles.blankslate}>
        <Blankslate.Visual>
          <img src="images/mona-happy.gif" alt="Happy Mona" />
        </Blankslate.Visual>
        <Blankslate.Heading as="h3">You finished your onboarding tasks!</Blankslate.Heading>
        <Blankslate.Description>
          Now the real magic begins when you ship something amazing. Continue to check out tutorials, best practices,
          and docs to get the most out of GitHub.
        </Blankslate.Description>
        <Button variant="default" onClick={onDismiss}>
          Dismiss
        </Button>
      </Blankslate>
    </Stack>
  )
}
