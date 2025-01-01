import {testIdProps} from '@github-ui/test-id-props'
import {GlobeIcon, LockIcon, PencilIcon, ProjectTemplateIcon} from '@primer/octicons-react'
import {IconButton, Label} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {clsx} from 'clsx'
import type {SpaceProps, TypographyProps} from 'styled-system'

import {ViewerPrivileges} from '../../helpers/viewer-privileges'
import {useNavigate} from '../../router'
import {useProjectRouteParams} from '../../router/use-project-route-params'
import {PROJECT_SETTINGS_ROUTE} from '../../routes'
import {useProjectDetails} from '../../state-providers/memex/use-project-details'
import {useProjectState} from '../../state-providers/memex/use-project-state'
import {SanitizedHtml} from '../dom/sanitized-html'
import {PROJECT_NAME_INPUT_ID} from '../shared-ids'
import styles from './memex-title.module.css'

export const MemexTitle: React.FC<TypographyProps & SpaceProps> = () => {
  const {hasWritePermissions} = ViewerPrivileges()
  const {shortDescriptionHtml, titleHtml} = useProjectDetails()
  const {isPublicProject, isClosed, isTemplate} = useProjectState()
  const navigate = useNavigate()
  const visibility = isPublicProject ? 'Public' : 'Private'
  const projectRouteParams = useProjectRouteParams()

  const onEditClick = () => {
    navigate(PROJECT_SETTINGS_ROUTE.generatePath(projectRouteParams))
    setTimeout(() => document.getElementById(PROJECT_NAME_INPUT_ID)?.focus())
  }

  const projectIcon = () => {
    if (isPublicProject && isTemplate) {
      return ProjectTemplateIcon
    }

    if (!isPublicProject) {
      return LockIcon
    }

    return GlobeIcon
  }

  return (
    <div>
      <div className={styles.Box}>
        {/* eslint eslint-comments/no-use: off */
        /* eslint-disable-next-line jsx-a11y/no-static-element-interactions, jsx-a11y/click-events-have-key-events */}
        <div
          // normally an onClick handler on a Box with no role would be inaccessible, but we're also providing the edit
          // button as a focusable child so all this is doing is expanding the clickable area for the button.
          onClick={hasWritePermissions ? onEditClick : undefined}
          className={clsx(styles.Box_1, {
            [styles.Box_1__hasWritePermissions]: hasWritePermissions,
          })}
        >
          {isClosed ? <ClosedLabel /> : null}

          <Octicon icon={projectIcon()} className={styles.Octicon} />

          <SanitizedHtml as="h1" className={styles.SanitizedHtml}>
            {titleHtml}
          </SanitizedHtml>
          {hasWritePermissions && (
            <IconButton
              id="edit-project-name-button"
              icon={PencilIcon}
              variant="invisible"
              size="small"
              onClick={onEditClick}
              aria-label="Edit project name"
              className={styles.IconButton}
            />
          )}
        </div>

        {isTemplate ? <Label variant="secondary"> {visibility} template </Label> : null}
      </div>
      {isTemplate && (
        <div>
          <SanitizedHtml as="div" className="color-fg-muted">
            {shortDescriptionHtml}
          </SanitizedHtml>
        </div>
      )}
    </div>
  )
}

const ClosedLabel = () => (
  <Label variant="done" {...testIdProps('closed-project-label')} className={styles.Label}>
    Closed
  </Label>
)
