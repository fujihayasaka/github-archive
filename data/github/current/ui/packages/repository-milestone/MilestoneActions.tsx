import {CreateIssueButton} from '@github-ui/issue-create/CreateIssueButton'
import {noop} from '@github-ui/noop'
import {Button} from '@primer/react'
import {useFragment} from 'react-relay'
import {graphql} from 'relay-runtime'
import {LABELS} from './constants/labels'
import styles from './RepositoryMilestone.module.css'
import {ToggleMilestoneState} from './ToggleMilestoneState'
import {ssrSafeLocation} from '@github-ui/ssr-utils'
import {useNavigate} from '@github-ui/use-navigate'
import {useCallback} from 'react'
import type {MilestoneActions$key} from './__generated__/MilestoneActions.graphql'
import type {UserSettingsOptionConfig} from '@github-ui/issue-create/getSafeConfig'
import {MilestoneTitle} from './MilestoneTitle'

type MilestoneActionsProps = {
  repositoryRef: MilestoneActions$key
  optionConfig?: UserSettingsOptionConfig
}

export function MilestoneActions({repositoryRef, optionConfig}: MilestoneActionsProps) {
  const {milestone, viewerCanPush, owner, name} = useFragment(
    graphql`
      fragment MilestoneActions on Repository @argumentDefinitions(number: {type: "Int!"}) {
        milestone(number: $number) {
          ...ToggleMilestoneState
          ...MilestoneTitle
          number
          title
        }
        viewerCanPush
        owner {
          login
        }
        name
      }
    `,
    repositoryRef,
  )
  const navigate = useNavigate()

  const navigateToMilestoneFn = useCallback(
    (url: string) => {
      if (!milestone || !milestone.title) return
      const milestoneParam = `milestone=${encodeURIComponent(milestone.title)}`
      const urlWithMilestone = url.includes('?') ? `${url}&${milestoneParam}` : `${url}?${milestoneParam}`
      navigate(urlWithMilestone)
    },
    [milestone, navigate],
  )

  if (!milestone) return null

  const rootUrl = `${ssrSafeLocation.origin}/${owner.login}/${name}`
  const editMilestoneUrl = `${rootUrl}/milestones/${milestone.number}/edit`

  return (
    <div className={`${styles.buttonGrp} ${styles.header}`}>
      <MilestoneTitle milestoneRef={milestone} />
      <div className={styles.actionsGrp}>
        {viewerCanPush ? (
          <>
            <Button as="a" href={editMilestoneUrl}>
              {LABELS.editMilestone}
            </Button>

            <ToggleMilestoneState milestoneRef={milestone} />
          </>
        ) : null}
        <CreateIssueButton
          label={LABELS.newIssue}
          navigate={navigateToMilestoneFn}
          optionConfig={{
            ...optionConfig,
            showRepositoryPicker: false,
            issueCreateArguments: {
              repository: {
                owner: owner.login,
                name,
              },
            },
            showFullScreenButton: true,
            navigateToFullScreenOnTemplateChoice: navigate !== noop,
            canBypassTemplateSelection: true,
          }}
        />
      </div>
    </div>
  )
}
