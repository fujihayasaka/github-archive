import {announce} from '@github-ui/aria-live'
import {noop} from '@github-ui/noop'
import {
  ArrowLeftIcon,
  GraphIcon,
  ProjectTemplateIcon,
  SearchIcon,
  WorkflowIcon,
  XCircleFillIcon,
} from '@primer/octicons-react'
import {Button, CounterLabel, FormControl, Heading, NavList, TextInput, useTheme} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {Blankslate, Dialog} from '@primer/react/experimental'
import {formatDistanceToNow} from 'date-fns'
import debounce from 'lodash-es/debounce'
import {useCallback, useEffect, useMemo, useState} from 'react'

import type {CustomTemplate} from '../../api/common-contracts'
import type {GetCustomTemplatesResponse, SystemTemplate} from '../../api/memex/contracts'
import {TemplatesCancel, TemplatesCreate} from '../../api/stats/contracts'
import {useApplyTemplate} from '../../features/templates/hooks/use-apply-template'
import {getInitialState} from '../../helpers/initial-state'
import {useThemedMediaUrl} from '../../helpers/media-urls'
import {getViewIcons, ViewType} from '../../helpers/view-type'
import {usePostStats} from '../../hooks/common/use-post-stats'
import {useOrganizationTemplates} from '../../queries/org-templates'
import {Link, useSearchParams} from '../../router'
import {useProjectDetails} from '../../state-providers/memex/use-project-details'
import {useTemplateDialog} from '../../state-providers/template-dialog/use-template-dialog'
import {getColumnIcon} from '../column-detail-helpers'
import {EmojiAutocomplete} from '../common/emoji-autocomplete'
import {FeaturedTemplateCard} from './featured-template-card'
import {
  CustomTemplateParam,
  LayoutTemplateParam,
  type SelectedTemplate,
  SystemTemplateParam,
  useTemplateLink,
} from './hooks/use-template-link'
import {infoContentMap} from './main-content-data'
import {TemplateList} from './template-list'
import styles from './TemplateDialog.module.css'

/** Number of organization templates to preview in the "all templates" tab */
const numberOfTemplatesToPreview = 6

/** Number of system/featured templates to preview in the "all templates tab" */
const numberOfSystemTemplatesToPreview = 2

export const TemplateDialogTabParam = 'template_dialog_tab'
export const TemplateDialogTab = {ALL: 'all', FEATURED: 'featured', ORG: 'organization'} as const
export type TemplateDialogTab =
  | typeof TemplateDialogTab.ALL
  | typeof TemplateDialogTab.FEATURED
  | typeof TemplateDialogTab.ORG

function useCurrentTab(): TemplateDialogTab {
  const {isOrganization} = getInitialState()
  const currentTabSearchParam = useSearchParams()[0].get(TemplateDialogTabParam) ?? TemplateDialogTab.ALL
  if (!isOrganization) {
    // For user projects, the only applicable options is the featured system templates, as there are no org templates
    return TemplateDialogTab.FEATURED
  }
  if (
    currentTabSearchParam === TemplateDialogTab.ALL ||
    currentTabSearchParam === TemplateDialogTab.FEATURED ||
    currentTabSearchParam === TemplateDialogTab.ORG
  ) {
    return currentTabSearchParam
  }
  return TemplateDialogTab.ALL
}

function useSelectedTemplate({
  organizationTemplates,
}: {
  organizationTemplates: Array<CustomTemplate>
}): undefined | SelectedTemplate {
  const [searchParams] = useSearchParams()
  const customProjectTemplateNumber = searchParams.get(CustomTemplateParam)
  const systemTemplate = searchParams.get(SystemTemplateParam)
  const layoutTemplate = searchParams.get(LayoutTemplateParam)
  const selectedTemplate = useMemo(() => {
    if (systemTemplate) {
      const template = getInitialState().systemTemplates?.find(t => t.id.toLowerCase() === systemTemplate.toLowerCase())
      if (template) {
        return {type: 'system', template} as const
      }
    }
    if (customProjectTemplateNumber) {
      const customTemplate = organizationTemplates.find(
        template => template.projectNumber === Number(customProjectTemplateNumber),
      )
      if (customTemplate) {
        return {type: 'custom', template: customTemplate} as const
      }
    }
    if (layoutTemplate) {
      if (
        layoutTemplate === ViewType.Table ||
        layoutTemplate === ViewType.Board ||
        layoutTemplate === ViewType.Roadmap
      ) {
        return {type: 'layout', viewType: layoutTemplate} as const
      }
    }
  }, [customProjectTemplateNumber, layoutTemplate, organizationTemplates, systemTemplate])
  return selectedTemplate
}

function AllTemplatesTab({
  organizationTemplates,
  systemTemplates,
  previewTemplateCount = numberOfTemplatesToPreview,
  hideViewAll = false,
}: {
  organizationTemplates: GetCustomTemplatesResponse | null
  systemTemplates: Array<SystemTemplate>
  previewTemplateCount?: number
  /** Hide the "view all" links, e.g., when showing search results */
  hideViewAll?: boolean
}) {
  // Subset of organization templates to show on this tab
  const organizationTemplatesPreview = organizationTemplates
    ? (organizationTemplates.recommendedTemplates && organizationTemplates.recommendedTemplates.length > 0
        ? organizationTemplates.recommendedTemplates
        : organizationTemplates.templates
      ).slice(0, previewTemplateCount)
    : []
  const systemTemplatesPreview = systemTemplates.slice(0, numberOfSystemTemplatesToPreview)

  return (
    <div>
      {systemTemplatesPreview.length > 0 && (
        <div className={styles.Box}>
          <div className={styles.Box_1}>
            <Heading as="h2" className={styles.Heading}>
              Featured
            </Heading>
            {!hideViewAll && systemTemplates.length >= numberOfSystemTemplatesToPreview && (
              <Link to={`?${TemplateDialogTabParam}=${TemplateDialogTab.FEATURED}`} className={styles.Box_2}>
                View all
              </Link>
            )}
          </div>
          <div className={styles.templateGrid}>
            {systemTemplatesPreview.map(template => (
              <FeaturedTemplateCard key={template.id} template={template} />
            ))}
          </div>
        </div>
      )}
      {organizationTemplatesPreview.length > 0 && (
        <TemplateList
          title="From your organization"
          templates={organizationTemplatesPreview}
          metadata={
            hideViewAll ? undefined : <Link to={`?${TemplateDialogTabParam}=${TemplateDialogTab.ORG}`}>View all</Link>
          }
        />
      )}
    </div>
  )
}

function FeaturedTemplatesTab({
  systemTemplates,
  hideHeading = false,
}: {
  systemTemplates: Array<SystemTemplate>
  hideHeading?: boolean
}) {
  return (
    <div>
      {!hideHeading && (
        <Heading as="h2" className={styles.Heading}>
          Featured
        </Heading>
      )}
      <div className={styles.templateGrid}>
        {systemTemplates.map(template => (
          <FeaturedTemplateCard key={template.id} template={template} />
        ))}
      </div>
    </div>
  )
}

function OrganizationTemplatesTab({
  organizationTemplates,
  hideBlankslate = false,
}: {
  organizationTemplates: GetCustomTemplatesResponse
  hideBlankslate?: boolean
}) {
  if (organizationTemplates.templates.length === 0) {
    if (hideBlankslate) return null
    return (
      <Blankslate>
        <Blankslate.Visual>
          <ProjectTemplateIcon />
        </Blankslate.Visual>
        <Blankslate.Heading>No templates yet</Blankslate.Heading>
        <Blankslate.Description>
          Templates can be used to quickly get started with a new project.
        </Blankslate.Description>
        {/* Using a custom link action styling here instead of SecondaryAction, so that we can link to a new tab */}
        <div className={styles.Box_3}>
          <a
            target="_blank"
            rel="noopener noreferrer"
            href="https://docs.github.com/issues/planning-and-tracking-with-projects/managing-your-project/managing-project-templates-in-your-organization"
          >
            Learn more
          </a>
        </div>
      </Blankslate>
    )
  }

  return (
    <div>
      {organizationTemplates.recommendedTemplates && organizationTemplates.recommendedTemplates.length > 0 && (
        <div className={styles.Box}>
          <TemplateList title="Recommended" templates={organizationTemplates.recommendedTemplates} />
        </div>
      )}
      <div className={styles.Box}>
        <TemplateList title="All" templates={organizationTemplates.templates} />
      </div>
    </div>
  )
}

function DefaultTemplateImage({
  title,
  template,
}: {
  title: string
  template: Extract<SelectedTemplate, {type: 'system' | 'layout'}>
}) {
  // Only supported now for "layout templates"
  const assetName = template.type === 'layout' ? template.viewType : ''
  const oldImageUrl = useThemedMediaUrl('projectTemplateDialog', assetName)

  const {resolvedColorScheme} = useTheme()

  const imageUrl =
    template.type === 'layout'
      ? oldImageUrl
      : resolvedColorScheme === 'dark'
        ? template.template.imageUrl.dark
        : template.template.imageUrl.light

  return (
    <img
      src={imageUrl}
      alt={`Preview screenshot for template ${title}`}
      className={styles.defaultTemplateImageStyles}
    />
  )
}

/** Client-side implementation for the template search */
function useTemplateSearch({
  searchQuery,
  organizationTemplates,
}: {
  searchQuery: string
  organizationTemplates: GetCustomTemplatesResponse | null
}) {
  const currentTab = useCurrentTab()
  const filteredTemplates = useMemo(() => {
    const systemTemplates =
      getInitialState().systemTemplates?.filter(template => {
        return template.title.toLowerCase().includes(searchQuery.toLowerCase())
      }) ?? []
    const orgTemplates =
      organizationTemplates?.templates.filter(template =>
        template.projectTitle.toLowerCase().includes(searchQuery.toLowerCase()),
      ) ?? []
    return {organizationTemplates: orgTemplates, systemTemplates}
  }, [organizationTemplates, searchQuery])

  const showOrganizationTemplates = currentTab === TemplateDialogTab.ALL || currentTab === TemplateDialogTab.ORG
  const showSystemTemplates = currentTab === TemplateDialogTab.ALL || currentTab === TemplateDialogTab.FEATURED

  const totalCount =
    (showOrganizationTemplates ? filteredTemplates.organizationTemplates.length : 0) +
    (showSystemTemplates ? filteredTemplates.systemTemplates.length : 0)

  return {totalCount, filteredTemplates, showSearchResults: searchQuery.length > 0}
}

function TemplateDetails({
  template,
  onChangeProjectName,
  projectName,
}: {
  template: SelectedTemplate
  projectName: string
  onChangeProjectName: (newName: string) => void
}) {
  const fields = useMemo(() => {
    if (template.type === 'system') {
      // todo: add fields for system templates, currently we do not have this info anywhere
      return []
    }
    if (template.type === 'custom') {
      return template.template.projectFields.filter(({customField}) => customField)
    }
    if (template.type === 'layout') {
      return []
    }
    return []
  }, [template])

  const {title, description, updatedAt} = useMemo(() => {
    if (template.type === 'layout') {
      return infoContentMap(template.viewType)
    }

    if (template.type === 'system') {
      return {
        title: template.template.title,
        description: template.template.shortDescription,
      }
    }

    return {
      title: template.template.projectTitle,
      description: template.template.projectShortDescription,
      updatedAt: template.template.projectUpdatedAt,
    }
  }, [template])

  return (
    <div className={styles.templateDetails}>
      <div>
        <div>
          <Heading as="h2" className={styles.Heading_1}>
            {title}
          </Heading>
          {template.type === 'system' && <span className={styles.Box_5}> &bull; {'GitHub'}</span>}
        </div>
        {description && <p className={styles.Box_5}>{description}</p>}
        {updatedAt && (
          <p className={styles.Box_5}>
            Updated{' '}
            {formatDistanceToNow(new Date(updatedAt), {
              addSuffix: true,
            })}{' '}
          </p>
        )}
      </div>
      <div>
        <FormControl>
          <FormControl.Label>Project name</FormControl.Label>
          <EmojiAutocomplete fullWidth>
            <TextInput
              autoComplete="off"
              placeholder={title}
              value={projectName}
              onChange={e => onChangeProjectName(e.target.value)}
              className={styles.TextInput}
            />
          </EmojiAutocomplete>
        </FormControl>
        {template.type === 'system' || template.type === 'layout' ? (
          <DefaultTemplateImage title={title} template={template} />
        ) : null}
        {template.type === 'custom' && (
          <div className={styles.Box_6}>
            <div className={styles.pillRowStyles}>
              <div className={styles.pillRowLabelStyles}>
                <CounterLabel className={styles.CounterLabel}>{template.template.projectViews.length}</CounterLabel>
                Views
              </div>
              <div className={styles.pillContainerStyles}>
                {template.template.projectViews.map(view => (
                  <div key={view.name} className={styles.pillStyles}>
                    <Octicon icon={getViewIcons(view.viewType)} className={styles.pillIconStyles} />
                    {view.name}
                  </div>
                ))}
              </div>
            </div>
            <div className={styles.pillRowStyles}>
              <div className={styles.pillRowLabelStyles}>
                <CounterLabel className={styles.CounterLabel}>{fields.length}</CounterLabel>
                Fields
              </div>
              <div className={styles.pillContainerStyles}>
                {fields.map(field => (
                  <div key={field.name} className={styles.pillStyles}>
                    <Octicon icon={getColumnIcon(field.dataType)} className={styles.pillIconStyles} />
                    {field.name}
                  </div>
                ))}
              </div>
            </div>
            <div className={styles.pillRowStyles}>
              <div className={styles.pillRowLabelStyles}>
                <CounterLabel className={styles.CounterLabel}>{template.template.projectWorkflows.length}</CounterLabel>
                Workflows
              </div>
              <div className={styles.pillContainerStyles}>
                {template.template.projectWorkflows.map(workflow => (
                  <div key={workflow.name} className={styles.pillStyles}>
                    <Octicon icon={WorkflowIcon} className={styles.pillIconStyles} />
                    {workflow.name}
                  </div>
                ))}
              </div>
            </div>
            <div className={styles.pillRowStyles}>
              <div className={styles.pillRowLabelStyles}>
                <CounterLabel className={styles.CounterLabel}>{template.template.projectCharts.length}</CounterLabel>
                Insights
              </div>
              <div className={styles.pillContainerStyles}>
                {template.template.projectCharts.map(chart => (
                  <div key={chart.name} className={styles.pillStyles}>
                    <Octicon icon={GraphIcon} className={styles.pillIconStyles} />
                    {chart.name}
                  </div>
                ))}
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}

export function TemplateDialog() {
  const {postStats} = usePostStats()
  const [, setSearchParams] = useSearchParams()
  const {setIsTemplatesDialogOpen} = useTemplateDialog()
  const closeDialog = useCallback(() => {
    setSearchParams(params => {
      params.delete(TemplateDialogTabParam)
      params.delete(CustomTemplateParam)
      params.delete(SystemTemplateParam)
      params.delete(LayoutTemplateParam)
      return params
    })
    setIsTemplatesDialogOpen(false)
  }, [setIsTemplatesDialogOpen, setSearchParams])
  const currentTab = useCurrentTab()

  const {isOrganization} = getInitialState()
  const {data: organizationTemplates = null} = useOrganizationTemplates({
    enabled: isOrganization,
  })

  const selectedTemplate = useSelectedTemplate({organizationTemplates: organizationTemplates?.templates ?? []})
  const initialProjectTitle = useProjectDetails().title
  const [projectName, setProjectName] = useState(initialProjectTitle)
  const showTemplateDetails = !!selectedTemplate

  const {applyTemplate, isApplyingTemplate} = useApplyTemplate()
  const onCreateProject = useCallback(
    async (templateToApply: SelectedTemplate) => {
      await applyTemplate({
        template: templateToApply,
        title: projectName,
        rollback: noop,
      })

      // Send telemetry
      if (templateToApply.type === 'custom') {
        postStats({
          name: TemplatesCreate,
          context: JSON.stringify({
            template: 'org_templates',
            template_project_title: templateToApply.template?.projectTitle,
            template_project_number: templateToApply.template?.projectNumber,
          }),
          ui: 'template_dialog',
        })
      } else {
        postStats({
          name: TemplatesCreate,
          context: JSON.stringify({
            template: templateToApply.type === 'layout' ? templateToApply.viewType : templateToApply.template.id,
          }),
          ui: 'template_dialog',
        })
      }

      closeDialog()
    },
    [applyTemplate, closeDialog, postStats, projectName],
  )

  const tableTemplateLink = useTemplateLink({type: 'layout', viewType: ViewType.Table})
  const boardTemplateLink = useTemplateLink({type: 'layout', viewType: ViewType.Board})
  const roadmapTemplateLink = useTemplateLink({type: 'layout', viewType: ViewType.Roadmap})

  const [searchQuery, setSearchQuery] = useState('')
  const {totalCount, showSearchResults, filteredTemplates} = useTemplateSearch({searchQuery, organizationTemplates})

  const systemTemplates = getInitialState().systemTemplates ?? []
  const searchResults = totalCount === 0 ? 'No results' : totalCount === 1 ? '1 result' : `${totalCount} results`

  const debounceAnnouncement = debounce((announcement: string) => {
    announce(announcement, {assertive: true})
  }, 100)

  useEffect(() => {
    if (searchQuery) {
      debounceAnnouncement(searchResults)
    }
  }, [debounceAnnouncement, searchQuery, searchResults])

  return (
    <Dialog
      title="Create project"
      height="large"
      onClose={() => {
        postStats({name: TemplatesCancel})
        closeDialog()
      }}
      renderHeader={({dialogLabelId, onClose}) => (
        <Dialog.Header>
          <div className={styles.Box_11}>
            <div className={styles.Box_12}>
              {showTemplateDetails && (
                <Link to={{search: `?${TemplateDialogTabParam}=${currentTab}`}} aria-label="Back">
                  <Octicon icon={ArrowLeftIcon} className={styles.Box_5} />
                </Link>
              )}
              <Dialog.Title id={dialogLabelId}>Create project</Dialog.Title>
            </div>
            <Dialog.CloseButton onClose={() => onClose('close-button')} />
          </div>
        </Dialog.Header>
      )}
      renderBody={() => (
        <>
          <Dialog.Body>
            {showTemplateDetails && selectedTemplate ? (
              <TemplateDetails
                template={selectedTemplate}
                projectName={projectName}
                onChangeProjectName={setProjectName}
              />
            ) : (
              <div className={styles.templateDetails}>
                <NavList className={styles.NavList}>
                  <NavList.Group title="Project templates">
                    {isOrganization && (
                      <NavList.Item
                        as={Link}
                        aria-current={currentTab === TemplateDialogTab.ALL ? 'page' : false}
                        to={`?${TemplateDialogTabParam}=${TemplateDialogTab.ALL}`}
                      >
                        All templates
                      </NavList.Item>
                    )}
                    <NavList.Item
                      as={Link}
                      aria-current={currentTab === TemplateDialogTab.FEATURED ? 'page' : false}
                      to={`?${TemplateDialogTabParam}=${TemplateDialogTab.FEATURED}`}
                    >
                      Featured
                    </NavList.Item>
                    {isOrganization && (
                      <NavList.Item
                        as={Link}
                        aria-current={currentTab === TemplateDialogTab.ORG ? 'page' : false}
                        to={`?${TemplateDialogTabParam}=${TemplateDialogTab.ORG}`}
                      >
                        From your organization
                      </NavList.Item>
                    )}
                  </NavList.Group>
                  <NavList.Group title="Start from scratch">
                    <NavList.Item as={Link} to={tableTemplateLink}>
                      Table
                    </NavList.Item>
                    <NavList.Item as={Link} to={boardTemplateLink}>
                      Board
                    </NavList.Item>
                    <NavList.Item as={Link} to={roadmapTemplateLink}>
                      Roadmap
                    </NavList.Item>
                  </NavList.Group>
                </NavList>
                <div>
                  <FormControl className={styles.FormControl}>
                    <FormControl.Label visuallyHidden>Search templates</FormControl.Label>
                    <TextInput
                      block
                      leadingVisual={SearchIcon}
                      placeholder="Search templates"
                      value={searchQuery}
                      onChange={e => setSearchQuery(e.target.value)}
                      trailingAction={
                        searchQuery.length > 0 ? (
                          <TextInput.Action
                            onClick={() => setSearchQuery('')}
                            icon={XCircleFillIcon}
                            aria-label="Clear search"
                            className={styles.Box_5}
                          />
                        ) : undefined
                      }
                    />
                  </FormControl>
                  <Heading as="h2" className={styles.Heading_2}>
                    {showSearchResults ? searchResults : ''}
                  </Heading>
                  {currentTab === TemplateDialogTab.ALL && (
                    <AllTemplatesTab
                      organizationTemplates={
                        showSearchResults ? {templates: filteredTemplates.organizationTemplates} : organizationTemplates
                      }
                      systemTemplates={showSearchResults ? filteredTemplates.systemTemplates : systemTemplates}
                      // If we are showing the search results, show a flat list of matching templates instead of just
                      // a preview of the total templates
                      previewTemplateCount={showSearchResults ? 100 : undefined}
                      hideViewAll={showSearchResults}
                    />
                  )}
                  {currentTab === TemplateDialogTab.FEATURED && (
                    <FeaturedTemplatesTab
                      systemTemplates={showSearchResults ? filteredTemplates.systemTemplates : systemTemplates}
                      hideHeading={showSearchResults}
                    />
                  )}
                  {currentTab === TemplateDialogTab.ORG && organizationTemplates && (
                    <OrganizationTemplatesTab
                      organizationTemplates={
                        showSearchResults ? {templates: filteredTemplates.organizationTemplates} : organizationTemplates
                      }
                      hideBlankslate={showSearchResults}
                    />
                  )}
                </div>
              </div>
            )}
          </Dialog.Body>
          {/* We are rendering a custom footer here because we want to conditionally show the footer depending on
              whether we are on the details page. However, we need to consistently render the footer area so that it
              is part of the focus trap. */}
          <Dialog.Footer sx={{display: showTemplateDetails && selectedTemplate ? undefined : 'none'}}>
            {showTemplateDetails && selectedTemplate ? (
              <Button variant="primary" disabled={isApplyingTemplate} onClick={() => onCreateProject(selectedTemplate)}>
                Create project
              </Button>
            ) : null}
          </Dialog.Footer>
        </>
      )}
      className={styles.Dialog}
    />
  )
}

export function TemplateDialogWrapper() {
  const {showTemplateDialog} = getInitialState()
  const {isTemplatesDialogOpen} = useTemplateDialog()

  return showTemplateDialog && isTemplatesDialogOpen ? <TemplateDialog /> : null
}
