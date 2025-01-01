import {testIdProps} from '@github-ui/test-id-props'
import {Button, Heading, useConfirm} from '@primer/react'
import {useCallback, useEffect, useState} from 'react'
import {useBlocker} from 'react-router-dom'

import {SuccessState} from '../../../components/common/state-style-decorators'
import {DescriptionEditor} from '../../../components/description-editor'
import {ShortDescriptionEditor} from '../../../components/short-description-editor'
import {useProjectDetails} from '../../../state-providers/memex/use-project-details'
import {
  ProjectNameRequiredError,
  useUpdateMemexSettings,
} from '../../../state-providers/memex/use-update-memex-settings'
import {Resources} from '../../../strings'
import {ProjectNameEditor} from './project-name-editor'
import styles from './project-settings-form.module.css'

export function ProjectSettingsForm() {
  const {title} = useProjectDetails()
  const {
    updateSettings,
    isSuccess: isUpdateMemexSuccess,
    isError: isUpdateMemexError,
    setSettings: setProjectSettings,
    isDirty,
  } = useUpdateMemexSettings()

  const setLocalProjectName = useCallback(
    (newTitle: string) => setProjectSettings({title: newTitle}),
    [setProjectSettings],
  )
  const setLocalProjectShortDescription = useCallback(
    (newShortDescription: string) => setProjectSettings({shortDescription: newShortDescription}),
    [setProjectSettings],
  )
  const setLocalProjectDescription = useCallback(
    (newDescription: string) => setProjectSettings({description: newDescription}),
    [setProjectSettings],
  )

  const confirm = useConfirm()
  const [shouldNavigate, setShouldNavigate] = useState(false)

  const blocker = useBlocker(({currentLocation, nextLocation}) => {
    if (isDirty && currentLocation.pathname !== nextLocation.pathname) {
      confirmUnsavedChanges()
      return true
    }

    return false
  })

  const confirmUnsavedChanges = useCallback(async () => {
    setShouldNavigate(
      await confirm({
        title: 'Discard changes?',
        content: <div>You have unsaved changes. Are you sure you want leave this page and discard them?</div>,
        confirmButtonContent: 'Discard',
        confirmButtonType: 'danger',
      }),
    )
  }, [confirm])

  useEffect(() => {
    if (blocker && blocker.state === 'blocked') {
      if (shouldNavigate) {
        blocker.proceed()
      } else {
        blocker.reset()
      }
    }
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [shouldNavigate])

  return (
    <>
      <Heading as="h2" className={styles.Heading}>
        Project settings
      </Heading>
      <ProjectNameEditor initialValue={title} setLocalProjectName={setLocalProjectName} />
      <div className={styles.Box} {...testIdProps('readme-edit')}>
        <ShortDescriptionEditor setProjectShortDescription={setLocalProjectShortDescription} editModeOff />
      </div>
      <div {...testIdProps('readme-edit')}>
        <DescriptionEditor setProjectDescription={setLocalProjectDescription} editModeOff />
      </div>
      <div className={styles.Box_1}>
        <Button
          size="medium"
          variant="primary"
          onClick={updateSettings}
          className={styles.Button}
          {...testIdProps('save-project-settings-button')}
        >
          Save changes
        </Button>
        {isUpdateMemexSuccess && (
          <>
            <span {...testIdProps('save-project-settings-success')} className={styles.Text}>
              Saved
            </span>{' '}
            <SuccessState />
          </>
        )}
        {isUpdateMemexError && (
          <span {...testIdProps('save-project-settings-success')} className={styles.Text_1}>
            {isUpdateMemexError === ProjectNameRequiredError
              ? Resources.genericFormErrorMessage
              : Resources.genericErrorMessage}
          </span>
        )}
      </div>
    </>
  )
}
