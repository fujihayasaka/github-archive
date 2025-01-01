import {ActionList, type SxProp} from '@primer/react'

import {LABELS} from './constants/labels'
import {TEST_IDS} from './constants/test-ids'
import {useIssueCreateConfigContext} from './contexts/IssueCreateConfigContext'
import {DisplayMode} from './utils/display-mode'
import styles from './TemplateList.module.css'
import {IssueFormRow} from './IssueFormRow'
import {IssueTemplateRow} from './IssueTemplateRow'
import {ExternalLinkTemplateRow} from './ExternalLinkTemplateRow'
import {useFragment} from 'react-relay'
import {graphql} from 'relay-runtime'
import type {TemplateList$data, TemplateList$key} from './__generated__/TemplateList.graphql'
import {BlankIssueItem} from './BlankIssueItem'
import {SecurityPolicyRow} from './SecurityPolicyRow'
import {TemplateListPaneFooter} from './TemplateListPaneFooter'
import {BLANK_ISSUE_ID, type IssueCreationKind} from './utils/model'
import {IssuesLoadingSkeleton} from '@github-ui/issues-loading-skeleton'
import {newTemplateAbsolutePath} from './utils/urls'
import {ssrSafeLocation} from '@github-ui/ssr-utils'
import {isFeatureEnabled} from '@github-ui/feature-flags'

type TemplateListProps = {
  repository: TemplateList$key
  className?: string
} & TemplateListSelectedProp &
  TemplateListSharedProps &
  SxProp

export type TemplateListSelectedProp = {
  onTemplateSelected?: (filename: string, kind: IssueCreationKind) => void
}

export type TemplateListSharedProps = {
  setIsNavigatingToNew?: React.Dispatch<React.SetStateAction<boolean>>
  isNavigatingToNew?: boolean
}

// This function will return a non-null URL if there's only one possible selection
function getDirectUrlToIssueCreate(data: TemplateList$data) {
  if (data.contactLinks && data.contactLinks.length > 0) return null
  if (data.isSecurityPolicyEnabled && data.securityPolicyUrl) return null
  if (data.isBlankIssuesEnabled) return null

  let singleTemplateOrFormFilename: string | null = null
  if (data.issueForms) {
    if (data.issueForms.length === 1) {
      singleTemplateOrFormFilename = data.issueForms[0]!.filename
    } else if (data.issueForms.length > 1) {
      // More than one form, no need to check templates
      return null
    }
  }

  if (data.issueTemplates) {
    if (singleTemplateOrFormFilename) {
      if (data.issueTemplates.length > 0) {
        // One form and at least one template
        return null
      }
    } else {
      if (data.issueTemplates.length === 1) {
        singleTemplateOrFormFilename = data.issueTemplates[0]!.filename
      }
    }
  }

  if (!singleTemplateOrFormFilename) return null

  const origin = ssrSafeLocation?.origin ?? ''
  const repositoryAbsolutePath = `${origin}/${data.nameWithOwner}`

  return newTemplateAbsolutePath({repositoryAbsolutePath, fileName: singleTemplateOrFormFilename})
}

export function TemplateList({repository, onTemplateSelected, className, setIsNavigatingToNew}: TemplateListProps) {
  const {optionConfig, displayMode} = useIssueCreateConfigContext()
  const data = useFragment(
    graphql`
      fragment TemplateList on Repository {
        id
        nameWithOwner
        issueForms {
          __typename
          filename
          ...IssueFormRow
        }
        issueTemplates {
          __typename
          filename
          ...IssueTemplateRow
        }
        isBlankIssuesEnabled
        isSecurityPolicyEnabled
        securityPolicyUrl
        contactLinks {
          name
          ...ExternalLinkTemplateRow
        }
        hasAnyTemplates
      }
    `,
    repository,
  )

  if (!data.hasAnyTemplates && !data.isBlankIssuesEnabled) {
    return <span>{LABELS.noTemplates}</span>
  }

  // it's about nav straight to the first template when blankIssues are disabled and repo has 1 template only
  if (optionConfig.canBypassTemplateSelection) {
    const directHrefToIssueCreate = getDirectUrlToIssueCreate(data)
    if (directHrefToIssueCreate) {
      setIsNavigatingToNew?.(true)
      optionConfig.navigate?.(directHrefToIssueCreate)
      return null
    } else {
      setIsNavigatingToNew?.(false)
    }
  }

  // Combine forms and templates and sort alphabetically
  const issueForms = data.issueForms || []
  const issueTemplates = data.issueTemplates || []
  const combinedTemplateItems = [...issueForms, ...issueTemplates]
    .sort((a, b) => {
      return a.filename.localeCompare(b.filename)
    })
    .map(template => {
      if (template.__typename === 'IssueForm') {
        return (
          <IssueFormRow
            key={template.filename}
            onTemplateSelected={onTemplateSelected}
            form={template}
            nameWithOwner={data.nameWithOwner}
          />
        )
      }
      return (
        <IssueTemplateRow
          key={template.filename}
          onTemplateSelected={onTemplateSelected}
          template={template}
          nameWithOwner={data.nameWithOwner}
        />
      )
    })

  const templateContent = (
    <>
      {combinedTemplateItems}
      {data.isBlankIssuesEnabled && (
        <BlankIssueItem
          key={BLANK_ISSUE_ID}
          onTemplateSelected={onTemplateSelected}
          nameWithOwner={data.nameWithOwner}
        />
      )}
      {data.isSecurityPolicyEnabled && <SecurityPolicyRow key="security_policy" link={data.securityPolicyUrl} />}
      {data.contactLinks &&
        data.contactLinks.map(link => (
          <ExternalLinkTemplateRow key={`contact_links.${link.name}`} repositoryContactLink={link} />
        ))}
    </>
  )

  const shouldShowFooter = isFeatureEnabled('issues_react_create_issue_with_copilot_cta')

  return (
    <>
      <ActionList className={className} data-testid={TEST_IDS.templateList} showDividers variant={'inset'}>
        {optionConfig.showRepositoryPicker && displayMode === DisplayMode.TemplatePicker ? (
          <ActionList.Group>
            <ActionList.GroupHeading
              as={'h2'}
              variant="filled"
              className={`position-sticky top-0 x ${!optionConfig.insidePortal && 'border-top-0'} ${
                styles.templateHeader
              }`}
            >
              {LABELS.templatesFormsTitle}
            </ActionList.GroupHeading>
            {templateContent}
          </ActionList.Group>
        ) : (
          templateContent
        )}
      </ActionList>
      {shouldShowFooter && <TemplateListPaneFooter />}
    </>
  )
}

const loadingSkeletonWidths = ['220px', '250px', '290px', '210px'].map((width, index) => ({
  id: `skeleton-${index}`,
  width,
}))

export function TemplateListLoading() {
  const {optionConfig} = useIssueCreateConfigContext()

  return (
    <div className={`${styles.skeletonContainer} ${optionConfig.insidePortal && 'ml-3'}`}>
      {loadingSkeletonWidths.map(({id, width}) => (
        <IssuesLoadingSkeleton key={id} height="xl" width={width} />
      ))}
    </div>
  )
}

export function NoTemplates({id}: {id?: string}) {
  return <span id={id}>{LABELS.noTemplates}</span>
}
