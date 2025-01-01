import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import type {AppPayload} from '../../types/app-payload'
import {useNavigate} from '@github-ui/use-navigate'
import {graphql, useFragment} from 'react-relay'
import {useUser} from '@github-ui/use-user'
import styles from './SearchBarActions.module.css'
import {Button} from '@primer/react'
import {MilestoneIcon, TagIcon} from '@primer/octicons-react'
import {CreateIssueButton} from '@github-ui/issue-create/CreateIssueButton'
import {BUTTON_LABELS} from '../../constants/buttons'
import {noop} from '@github-ui/noop'
import type {SearchBarActionsRepositoryFragment$key} from './__generated__/SearchBarActionsRepositoryFragment.graphql'

type SearchBarActionsProps = {
  currentRepository: SearchBarActionsRepositoryFragment$key | null
}

export function SearchBarActions({currentRepository}: SearchBarActionsProps) {
  const navigate = useNavigate()
  const {currentUser} = useUser()
  const {scoped_repository, current_user_settings, paste_url_link_as_plain_text} = useAppPayload<AppPayload>()
  const repository_data = useFragment(
    graphql`
      fragment SearchBarActionsRepositoryFragment on Repository {
        isOwnerEnterpriseManaged
      }
    `,
    currentRepository,
  )
  const hideCreateButton =
    scoped_repository?.is_archived || // archived repo
    (currentUser != null && !!currentUser?.is_emu && (!repository_data || !repository_data.isOwnerEnterpriseManaged)) // emu user in a non-owned repo

  return (
    <div className={`${styles.buttons} ${styles.gap8} d-flex flex-wrap`}>
      <Button as="a" href={`labels`} leadingVisual={TagIcon}>
        Labels
      </Button>
      <Button as="a" href={`milestones`} leadingVisual={MilestoneIcon}>
        Milestones
      </Button>
      {!hideCreateButton && (
        <CreateIssueButton
          label={BUTTON_LABELS.newIssue}
          navigate={navigate}
          optionConfig={{
            scopedRepository: scoped_repository,
            useMonospaceFont: current_user_settings?.use_monospace_font || false,
            emojiSkinTonePreference: current_user_settings?.preferred_emoji_skin_tone,
            singleKeyShortcutsEnabled: current_user_settings?.use_single_key_shortcut || false,
            pasteUrlsAsPlainText: paste_url_link_as_plain_text,
            // Only navigate if we're in the Repo#Index (ie, have a scoped repository)
            navigateToFullScreenOnTemplateChoice: navigate !== noop && scoped_repository !== null,
            showFullScreenButton: true,
          }}
        />
      )}
    </div>
  )
}
