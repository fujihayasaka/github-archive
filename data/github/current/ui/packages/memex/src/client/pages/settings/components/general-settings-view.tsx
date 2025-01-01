import {announce} from '@github-ui/aria-live'
import {IncludeFragment} from '@github-ui/include-fragment-react'
import {testIdProps} from '@github-ui/test-id-props'
import {CopyIcon, DuplicateIcon, GlobeIcon, LockIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, Button, Heading, Link, Text, ToggleSwitch} from '@primer/react'
import {useCallback, useEffect, useMemo, useState} from 'react'

import {apiResyncElasticsearchIndex} from '../../../api/memex-items/api-resync-elasticsearch-index'
import {
  CopyAsTemplate,
  CopyProject,
  CreatedWithTemplateClick,
  ProjectDescriptionSettingsPageUI,
  ProjectReadmeSettingsPageUI,
} from '../../../api/stats/contracts'
import {SuccessState} from '../../../components/common/state-style-decorators'
import {SanitizedHtml} from '../../../components/dom/sanitized-html'
import {getInitialState} from '../../../helpers/initial-state'
import {ViewerPrivileges} from '../../../helpers/viewer-privileges'
import {usePostStats} from '../../../hooks/common/use-post-stats'
import {useEnabledFeatures} from '../../../hooks/use-enabled-features'
import {useCreatedWithTemplateMemex} from '../../../state-providers/created-with-template-memex/created-with-template-memex-provider'
import {useDeleteMemex} from '../../../state-providers/memex/use-delete-memex'
import {useProjectDetails} from '../../../state-providers/memex/use-project-details'
import {useProjectNumber} from '../../../state-providers/memex/use-project-number'
import {useProjectState} from '../../../state-providers/memex/use-project-state'
import {useToggleMemexClose} from '../../../state-providers/memex/use-toggle-memex-close'
import {useToggleMemexPublic} from '../../../state-providers/memex/use-toggle-memex-public'
import {useUpdateMemexIsTemplate} from '../../../state-providers/memex/use-update-memex-is-template'
import {useMemexItems} from '../../../state-providers/memex-items/use-memex-items'
import {Resources, SettingsResources} from '../../../strings'
import {DeleteProjectDialog} from './delete-project-dialog'
import styles from './general-settings-view.module.css'
import {ProjectSettingsCard, ProjectSettingsCardBody, ProjectSettingsCardHeader} from './project-settings-card'
import {ProjectSettingsForm} from './project-settings-form'
import {RemoveTemplateDialog} from './remove-template-dialog'
import {ReorderCustomFieldsForm} from './reorder-custom-fields-form'

const consistencyColor = ({
  consistency,
  inconsistencyThreshold,
}: {
  consistency?: number
  inconsistencyThreshold?: number
}) => {
  if (!consistency || !inconsistencyThreshold) return 'fg.muted'
  if (consistency < inconsistencyThreshold * 100) return 'danger.fg'
  return 'success.fg'
}

export function GeneralSettingsView() {
  const {isClosed, isPublicProject, isTemplate} = useProjectState()
  const {isOrganization, projectOwner, copyProjectPartialUrl} = getInitialState()
  const {createdWithTemplateMemex} = useCreatedWithTemplateMemex()
  const {hasAdminPermissions, canChangeProjectVisibility, canCopyAsTemplate} = ViewerPrivileges()
  const {projectNumber} = useProjectNumber()
  const {toggleMemexClose} = useToggleMemexClose()
  const {toggleMemexPublic} = useToggleMemexPublic()
  const [visibilityState, setVisibilityState] = useState('')
  const {postStats} = usePostStats()
  const canDeleteProjects = hasAdminPermissions
  const [isDeleteProjectDialogOpen, setIsDeleteProjectDialogOpen] = useState(false)
  const {updateIsTemplate} = useUpdateMemexIsTemplate()
  const [isTemplateDialogOpen, setIsTemplateDialogOpen] = useState(false)
  const [isTemplateResponseState, setIsTemplateResponseState] = useState('')
  const {deleteMemex} = useDeleteMemex()
  const {memex_table_without_limits, memex_resync_index} = useEnabledFeatures()
  const canResyncIndex = memex_table_without_limits && memex_resync_index && hasAdminPermissions
  const canMakeTemplate = hasAdminPermissions
  const showTemplatesSection = isOrganization && (canCopyAsTemplate || canMakeTemplate || createdWithTemplateMemex)

  const handleDeleteMemex = useCallback(
    (e: React.FormEvent<HTMLFormElement>) => {
      e.preventDefault()
      deleteMemex()
    },
    [deleteMemex],
  )

  const onMemexClose = useCallback(
    async (close: boolean) => {
      await toggleMemexClose(close)
    },
    [toggleMemexClose],
  )

  const onMemexPublic = useCallback(
    async (setPublic: boolean) => {
      try {
        if (isPublicProject !== setPublic) {
          await toggleMemexPublic(setPublic)
          setVisibilityState('success')
        }
      } catch {
        setVisibilityState('error')
      }
    },
    [toggleMemexPublic, isPublicProject],
  )

  const resetNetworkCall = useCallback(() => {
    if (visibilityState) {
      setVisibilityState('')
    }
  }, [visibilityState, setVisibilityState])

  const {title, consistency, inconsistencyThreshold} = useProjectDetails()
  const memexItems = useMemexItems().items
  const canSeeConsistencyMetric = hasAdminPermissions && memex_resync_index && !!inconsistencyThreshold

  const draftIssueCount = useMemo(
    () => memexItems.filter(item => item.contentType === 'DraftIssue').length,
    [memexItems],
  )

  const postMakeCopyStats = useCallback(() => {
    postStats({
      name: CopyProject,
      ui: ProjectReadmeSettingsPageUI,
    })
  }, [postStats])

  const postCopyAsTemplateStats = useCallback(() => {
    postStats({
      name: CopyAsTemplate,
      ui: ProjectReadmeSettingsPageUI,
    })
  }, [postStats])

  const onClickLinkedTemplateMemex = useCallback(() => {
    postStats({
      name: CreatedWithTemplateClick,
      ui: ProjectDescriptionSettingsPageUI,
      context: JSON.stringify({
        templateMemexId: createdWithTemplateMemex?.id,
      }),
    })
  }, [postStats, createdWithTemplateMemex])

  const projectVisibilityDescription = useMemo(() => {
    if (canChangeProjectVisibility && isPublicProject) {
      return projectOwner?.isEnterpriseManaged ? SettingsResources.projectIsInternal : SettingsResources.projectIsPublic
    }

    if (canChangeProjectVisibility) {
      return SettingsResources.projectIsPrivate
    }

    if (isOrganization) {
      return SettingsResources.organizationOwnedProjectVisibilityRestriction
    }

    return SettingsResources.userOwnedProjectVisibilityRestriction
  }, [canChangeProjectVisibility, isPublicProject, isOrganization, projectOwner?.isEnterpriseManaged])

  const projectVisibilityButtonLabel = isPublicProject
    ? projectOwner?.isEnterpriseManaged
      ? 'Internal'
      : 'Public'
    : 'Private'

  const handleTemplateSwitch = (props: string) => {
    if (props === 'confirm') {
      toggleIsTemplate(!isTemplate)
    }
    setIsTemplateDialogOpen(false)
  }

  const toggleIsTemplate = useCallback(
    async (setIsTemplate: boolean) => {
      try {
        if (isTemplate !== setIsTemplate) {
          await updateIsTemplate(setIsTemplate)
          setIsTemplateResponseState('success')
          setTimeout(() => {
            setIsTemplateResponseState('')
          }, 1800)
        }
      } catch {
        setIsTemplateResponseState('error')
      }
    },
    [updateIsTemplate, isTemplate],
  )

  useEffect(() => {
    if (isTemplateResponseState === 'success') {
      announce(Resources.changesSaved)
    }
  }, [isTemplateResponseState, isTemplate])

  return (
    <div className={styles.Box} {...testIdProps('general-settings')}>
      <ProjectSettingsForm />
      {showTemplatesSection && (
        <>
          <Heading as="h2" className={styles.Heading}>
            Templates
          </Heading>
          {createdWithTemplateMemex && (
            <div className={styles.Box_1}>
              <p {...testIdProps('created-with-template-link')} className={styles.Text}>
                This project was created with the&nbsp;
                <Link inline target="_blank" href={createdWithTemplateMemex.url} onClick={onClickLinkedTemplateMemex}>
                  <SanitizedHtml>{createdWithTemplateMemex.titleHtml}</SanitizedHtml>
                </Link>
                &nbsp;template.
              </p>
            </div>
          )}
          <div className={styles.Box_2}>
            {canMakeTemplate && (
              <ProjectSettingsCard showDivider={canCopyAsTemplate}>
                <div className={styles.Box_1}>
                  <div id="make-template-label" className={styles.Box_3}>
                    Make template
                  </div>
                  <p id="make-template-description" className={styles.Text_1}>
                    Make this project a template that can be used by members of the <b>{projectOwner?.login}</b>{' '}
                    organization when creating new projects.
                  </p>
                  <div />
                </div>
                <ProjectSettingsCardBody>
                  <div className={styles.Box_4}>
                    {isTemplateResponseState === 'success' && (
                      <>
                        <SuccessState />
                        <span className={styles.Text_2}>Saved!</span>
                      </>
                    )}
                    {isTemplateResponseState === 'error' && <span className={styles.Text_3}>Something went wrong</span>}
                  </div>

                  <ToggleSwitch
                    aria-labelledby="make-template-label"
                    aria-describedby="make-template-description"
                    disabled={isClosed}
                    onClick={() => {
                      if (!isTemplate) {
                        toggleIsTemplate(!isTemplate)
                      }
                      setIsTemplateDialogOpen(isTemplate)
                    }}
                    checked={isTemplate}
                  />
                </ProjectSettingsCardBody>
              </ProjectSettingsCard>
            )}

            {canCopyAsTemplate && (
              <ProjectSettingsCard>
                <div className={styles.Box_1}>
                  <Heading as="h3" className={styles.Heading_1}>
                    Copy as template
                  </Heading>
                  <span>Copy this project into a template that can be used when creating new projects.</span>
                </div>
                <ProjectSettingsCardBody>
                  <IncludeFragment
                    key="settingsCopyAsTemplate"
                    src={encodeURI(`${copyProjectPartialUrl}?copy_as_template=true`)}
                  />
                  <Button
                    key="settingsCopyAsTemplateButton"
                    variant="default"
                    aria-label="Copy as template"
                    id={`settings-copy-as-template-dialog-${projectNumber}`}
                    data-show-dialog-id={`copy-as-template-dialog-${projectNumber}`}
                    leadingVisual={DuplicateIcon}
                    onClick={postCopyAsTemplateStats}
                    className={styles.Button_1}
                    {...testIdProps('copy-as-template-button')}
                  >
                    <span>Copy as template</span>
                  </Button>
                </ProjectSettingsCardBody>
              </ProjectSettingsCard>
            )}
          </div>
        </>
      )}
      {isTemplateDialogOpen && (
        <RemoveTemplateDialog
          isOpen={isTemplateDialogOpen}
          onClose={props => {
            handleTemplateSwitch(props)
          }}
        />
      )}
      <ReorderCustomFieldsForm />
      <Heading as="h2" className={styles.Heading}>
        More options
      </Heading>
      <div className={styles.Box_2}>
        <ProjectSettingsCard>
          <ProjectSettingsCardHeader title="Make a copy" description="Make a copy of this project." />
          <ProjectSettingsCardBody>
            <IncludeFragment key="settingsCopyProject" src={encodeURI(copyProjectPartialUrl)} />
            <Button
              key="settingsCopyProjectButton"
              variant="default"
              aria-label="Make a copy"
              id={`settings-copy-project-dialog-${projectNumber}`}
              data-show-dialog-id={`copy-project-dialog-${projectNumber}`}
              className={styles.Button_1}
              leadingVisual={CopyIcon}
              onClick={postMakeCopyStats}
            >
              <span>Make a copy</span>
            </Button>
          </ProjectSettingsCardBody>
        </ProjectSettingsCard>
      </div>
      <Heading as="h3" className={styles.Heading}>
        Danger zone
      </Heading>
      <div className={styles.Box_5}>
        <div className={styles.Box_6}>
          {hasAdminPermissions && (
            <ProjectSettingsCard showDivider>
              <div className={styles.Box_1}>
                <Heading as="h3" id="visibilityHeading" className={styles.Heading_1}>
                  Visibility
                </Heading>
                <span className={styles.Text_4} {...testIdProps('project-visibility-text')}>
                  {projectVisibilityDescription}
                </span>
              </div>
              <ProjectSettingsCardBody>
                <div className={styles.Box_7}>
                  <div className={styles.Box_8}>
                    <div aria-live="polite" {...testIdProps('project-visibility-update-status')}>
                      {visibilityState === 'success' && (
                        <>
                          <SuccessState />
                          <span className={styles.Text_2}>Changes saved</span>
                        </>
                      )}
                      {visibilityState === 'error' && <span className={styles.Text_3}>Something went wrong</span>}
                    </div>
                  </div>
                  <ActionMenu>
                    <ActionMenu.Button
                      {...testIdProps('project-visibility-button')}
                      onClick={resetNetworkCall}
                      aria-describedby="visibilityHeading"
                      leadingVisual={isPublicProject ? GlobeIcon : LockIcon}
                      disabled={!canChangeProjectVisibility}
                      className={styles.ActionMenu_Button}
                    >
                      {projectVisibilityButtonLabel}
                    </ActionMenu.Button>
                    <ActionMenu.Overlay anchorSide="inside-right">
                      <ActionList selectionVariant="single">
                        <ActionList.Item
                          key="private"
                          onSelect={() => onMemexPublic(false)}
                          selected={!isPublicProject}
                          className={styles.ActionList_Item}
                        >
                          Private
                          <ActionList.Description variant="block">
                            You choose who can read, write, and admin this project.
                          </ActionList.Description>
                        </ActionList.Item>
                        <ActionList.Item
                          key="public"
                          onSelect={() => onMemexPublic(true)}
                          selected={isPublicProject}
                          className={styles.ActionList_Item}
                        >
                          {projectOwner?.isEnterpriseManaged ? 'Internal' : 'Public'}
                          <ActionList.Description variant="block">
                            Everyone {projectOwner?.isEnterpriseManaged ? 'in your enterprise' : 'on the internet'} has
                            read access to this project. You choose who has write and admin access.
                          </ActionList.Description>
                        </ActionList.Item>
                      </ActionList>
                    </ActionMenu.Overlay>
                  </ActionMenu>
                </div>
              </ProjectSettingsCardBody>
            </ProjectSettingsCard>
          )}

          <ProjectSettingsCard showDivider={canDeleteProjects}>
            {isClosed ? (
              <>
                <ProjectSettingsCardHeader
                  title="Re-open project"
                  description="Re-opening a project will add it to the list of open projects."
                />
                <ProjectSettingsCardBody>
                  <Button {...testIdProps('reopen-project-button')} onClick={() => onMemexClose(false)}>
                    Re-open this project
                  </Button>
                </ProjectSettingsCardBody>
              </>
            ) : (
              <>
                <ProjectSettingsCardHeader
                  title="Close project"
                  description="Closing a project will disable its workflows & remove it from the list of open projects."
                />
                <ProjectSettingsCardBody>
                  <Button variant="danger" {...testIdProps('close-project-button')} onClick={() => onMemexClose(true)}>
                    Close this project
                  </Button>
                </ProjectSettingsCardBody>
              </>
            )}
          </ProjectSettingsCard>
          {canDeleteProjects && (
            <ProjectSettingsCard showDivider={canResyncIndex}>
              <ProjectSettingsCardHeader
                title="Delete project"
                description="Once you delete a project, there is no going back. Please be certain."
              />
              <ProjectSettingsCardBody>
                <Button
                  variant="danger"
                  {...testIdProps('delete-project-button')}
                  onClick={() => setIsDeleteProjectDialogOpen(true)}
                >
                  Delete this project
                </Button>
              </ProjectSettingsCardBody>
            </ProjectSettingsCard>
          )}
          {canResyncIndex && (
            <ProjectSettingsCard>
              <ProjectSettingsCardHeader
                title="Resync search index for this project"
                description="This will asynchronously correct inconsistencies between the search index and the database"
              >
                {canSeeConsistencyMetric && (
                  <>
                    <span className={styles.Text_4} {...testIdProps('resync-project-es-index-consistency-text')}>
                      {`The project data consistency with Elasticsearch is ${!consistency ? '' : 'at'} `}
                    </span>
                    <Text
                      sx={{
                        color: consistencyColor({consistency, inconsistencyThreshold}),
                      }}
                      className={styles.Text_4}
                      {...testIdProps('resync-project-es-index-consistency-value')}
                    >
                      {`${!consistency ? 'unknown' : `${consistency}%`}. `}
                    </Text>
                  </>
                )}
              </ProjectSettingsCardHeader>
              <ProjectSettingsCardBody>
                <Button
                  variant="danger"
                  {...testIdProps('resync-project-es-index-button')}
                  onClick={() => apiResyncElasticsearchIndex()}
                >
                  Resync search index
                </Button>
              </ProjectSettingsCardBody>
            </ProjectSettingsCard>
          )}
        </div>
      </div>
      {isDeleteProjectDialogOpen && (
        <DeleteProjectDialog
          onClose={() => setIsDeleteProjectDialogOpen(false)}
          projectName={title}
          onConfirm={handleDeleteMemex}
          draftIssueCount={draftIssueCount}
        />
      )}
    </div>
  )
}
