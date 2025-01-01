import {useChatState} from '@github-ui/copilot-chat/CopilotChatContext'
import {useChatManager} from '@github-ui/copilot-chat/CopilotChatManagerContext'
import {useSelectedCustomCopilotId} from '@github-ui/copilot-chat/hooks/use-selected-custom-copilot-id'
import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {getSelectedThread} from '@github-ui/copilot-chat/utils/get-selected-thread'
import InputLabel from '@github-ui/input-label'
import {useIssueCreateDataContext} from '@github-ui/issue-create/IssueCreateDataContext'
import {ItemPicker} from '@github-ui/item-picker/ItemPicker'
import {useQuery} from '@github-ui/react-query'
import {TriangleDownIcon} from '@primer/octicons-react'
import {Button} from '@primer/react'
import {clsx} from 'clsx'
import {useCallback, useEffect, useMemo, useRef, useState} from 'react'
import {useRelayEnvironment} from 'react-relay'
import {fetchQuery, graphql, readInlineData} from 'relay-runtime'

import type {TimelineEventTextReference} from '../../TimelineEvents'
import {type DraftIssue, makeReferenceFromVersionedItem} from '../content-preview-types'
import {useContentPreview} from '../ContentPreviewContext'
import type {TemplatePickerForm$data, TemplatePickerForm$key} from './__generated__/TemplatePickerForm.graphql'
import type {TemplatePickerQuery} from './__generated__/TemplatePickerQuery.graphql'
import type {
  TemplatePickerTemplate$data,
  TemplatePickerTemplate$key,
} from './__generated__/TemplatePickerTemplate.graphql'
import styles from './RepositoryPicker.module.css'

const TemplatesGraphqlQuery = graphql`
  query TemplatePickerQuery($owner: String!, $repo: String!) {
    repository(owner: $owner, name: $repo) {
      issueForms {
        __typename
        ...TemplatePickerForm
      }
      issueTemplates {
        __typename
        ...TemplatePickerTemplate
      }
    }
  }
`

const FormFragment = graphql`
  fragment TemplatePickerForm on IssueForm @inline {
    __typename
    filename
    name
    description
  }
`

const TemplateFragment = graphql`
  fragment TemplatePickerTemplate on IssueTemplate @inline {
    __typename
    filename
    name
    about
  }
`

type TemplatePickerItem = TemplatePickerTemplate$data | TemplatePickerForm$data

function isTemplate(item: TemplatePickerItem): item is TemplatePickerTemplate$data {
  return item.__typename === 'IssueTemplate'
}

function useTemplatesQuery({owner, repo}: {owner: string | undefined; repo: string | undefined}) {
  const environment = useRelayEnvironment()

  return useQuery({
    queryKey: ['copilot-immersive-templates', JSON.stringify(environment), owner, repo],
    queryFn: async () => {
      if (!owner || !repo) return []

      const data = await fetchQuery<TemplatePickerQuery>(environment, TemplatesGraphqlQuery, {owner, repo}).toPromise()

      const issueTemplates = (data?.repository?.issueTemplates || []).map(node => {
        // eslint-disable-next-line no-restricted-syntax
        return readInlineData<TemplatePickerTemplate$key>(TemplateFragment, node)
      })

      const issueForms = (data?.repository?.issueForms || []).map(node => {
        // eslint-disable-next-line no-restricted-syntax
        return readInlineData<TemplatePickerForm$key>(FormFragment, node)
      })

      return [...issueTemplates, ...issueForms].sort((a, b) => {
        return a.filename.localeCompare(b.filename)
      })
    },
  })
}

function useTemplateSelectedCallback() {
  const manager = useChatManager()
  const state = useChatState()
  const {updateItem} = useContentPreview()

  return useCallback(
    async (draftIssue: DraftIssue, template: TemplatePickerItem | undefined) => {
      const instructions: TimelineEventTextReference = {
        type: 'text',
        name: `timeline-event: {"type": "switch-issue-template", "markdownContent": "${
          template ? `Changing template to '${template.name}'…` : 'Removing template…'
        }"}`,
        text: template
          ? `Update the selected draft issue with the \`${template.filename}\` template. Regenerate the title and description following the new template. Maintain all conversation context. Update the metadata to follow the new template. DO NOT change the \`tag\` field.`
          : 'Update the selected draft issue to remove the template formatting. Regenerate the title and description to follow a generic format. Maintain all conversation context. DO NOT change the `tag` field.',
      }
      // Mark content preview items that correspond to the references as not user-edited so that they don't automatically
      // get closed when the chat reducer clears the currentReferences.
      // This is handled by ui/packages/copilot-immersive-v1/components/ConversationView.tsx for user submitted message but
      // we should find a way to share this logic.
      const updateDraftIssue = {...draftIssue, template: template?.filename, isUserEdited: false}
      updateItem(updateDraftIssue)
      // Since references of a supported type get "deserialized" back as a versioned item in content preview,
      // we make sure this version contains an updated template.
      const updatedDraftIssueRef = makeReferenceFromVersionedItem(updateDraftIssue)
      await manager.sendChatMessage({
        thread: getSelectedThread(state),
        content: template ? `Use the '${template.name}' template` : 'Remove the template',
        references: [instructions, updatedDraftIssueRef],
        topic: state.currentTopic,
        context: state.context,
        customInstructions: state.customInstructions,
        model: state.model,
      })
    },
    [manager, state, updateItem],
  )
}

export function TemplatePicker({draftIssue}: {draftIssue: DraftIssue}) {
  const spaceId = useSelectedCustomCopilotId()

  // Spaces currently uses the version of the draft-issue skill that does not include template support,
  // so we won't show the template picker in spaces until then.
  // https://github.com/github/copilot-voyager/issues/81
  if (spaceId != null) {
    return null
  }

  return <TemplatePickerWrapper {...{draftIssue}} />
}

function TemplatePickerWrapper({draftIssue}: {draftIssue: DraftIssue}) {
  const {repository} = useIssueCreateDataContext()
  const {data: templates} = useTemplatesQuery({
    owner: repository?.owner.login,
    repo: repository?.name,
  })

  if (templates == null || templates.length === 0) {
    return null
  }

  return (
    <>
      {/* this slash ends up as a breadcrumb separator between repo and template */}
      <span>/</span>
      <div className={styles.container}>
        <InputLabel className={clsx(styles.label, 'sr-only')}>Template</InputLabel>
        <TemplatePickerInternal {...{templates, draftIssue, isBlankIssuesEnabled: repository?.isBlankIssuesEnabled}} />
      </div>
    </>
  )
}

function TemplatePickerInternal({
  templates,
  draftIssue,
  isBlankIssuesEnabled,
}: {
  templates: TemplatePickerItem[]
  draftIssue: DraftIssue
  isBlankIssuesEnabled?: boolean
}) {
  const [filter, setFilter] = useState<string>('')
  const filteredItems = useMemo(() => {
    if (!filter) {
      return templates
    }
    return templates?.filter(item => {
      return item.name?.toLowerCase().includes(filter.toLowerCase())
    })
  }, [templates, filter])

  const [selectedItem, setSelectedItem] = useState<TemplatePickerItem | undefined>(undefined)
  useEffect(() => {
    if (!draftIssue.template) {
      setSelectedItem(undefined)
      return
    }
    const initTemplateFilename = draftIssue.template.split('/').pop()
    const selected = templates?.find(item => item.filename === initTemplateFilename)
    setSelectedItem(selected)
  }, [templates, draftIssue.template])
  const onTemplateSelected = useTemplateSelectedCallback()

  const templatePickerRef = useRef<HTMLButtonElement>(null)

  const templateRequired =
    copilotFeatureFlags.draftIssueTemplateRequiredIfBlankIssuesDisabled &&
    isBlankIssuesEnabled != null &&
    !isBlankIssuesEnabled

  return (
    <ItemPicker
      items={filteredItems ?? []}
      initialSelectedItems={selectedItem ? [selectedItem] : []}
      placeholderText={'Select template'}
      selectionVariant={'single'}
      filterItems={setFilter}
      renderAnchor={(props: React.HTMLAttributes<HTMLElement>): JSX.Element => {
        return (
          <Button trailingVisual={TriangleDownIcon} {...props} ref={templatePickerRef}>
            {selectedItem ? <span>{selectedItem.name}</span> : 'Select template'}
            {templateRequired && <span style={{color: 'red', marginLeft: 4}}>*</span>}
          </Button>
        )
      }}
      getItemKey={item => item.filename}
      convertToItemProps={item => ({
        id: item.filename,
        text: item.name,
        description: (isTemplate(item) ? item.about : item.description) || undefined,
        descriptionVariant: 'block',
        source: item,
      })}
      onSelectionChange={async ([item]) => {
        setSelectedItem(item)
        await onTemplateSelected(draftIssue, item)
      }}
      selectPanelRef={templatePickerRef}
      height={'large'}
      width={'medium'}
    />
  )
}
