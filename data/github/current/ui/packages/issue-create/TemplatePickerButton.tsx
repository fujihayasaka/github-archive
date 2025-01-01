import {PencilIcon, RepoIcon} from '@primer/octicons-react'
import {Box, Button, Text} from '@primer/react'
import type {IssueCreatePayload} from './utils/model'
import {useEffect, useRef} from 'react'
import {LABELS} from './constants/labels'
import {useIssueCreateConfigContext} from './contexts/IssueCreateConfigContext'
import {DisplayMode} from './utils/display-mode'
import {useFragment} from 'react-relay'
import {graphql} from 'relay-runtime'
import type {TemplatePickerButton$key} from './__generated__/TemplatePickerButton.graphql'

export type TemplatePickerButtonProps = {
  repository: TemplatePickerButton$key
  template: IssueCreatePayload | undefined
}

export function TemplatePickerButton({repository, template}: TemplatePickerButtonProps) {
  const data = useFragment(
    graphql`
      fragment TemplatePickerButton on Repository {
        nameWithOwner
        hasAnyTemplates
      }
    `,
    repository,
  )
  const {setDisplayMode} = useIssueCreateConfigContext()
  const templateText = template ? template.name : LABELS.blankIssueName
  const templatePickerButtonRef = useRef<HTMLButtonElement>(null)

  useEffect(() => {
    templatePickerButtonRef.current?.focus()
  }, [])

  if (!data.hasAnyTemplates) {
    return null
  }

  return (
    <Box sx={{width: 'content'}} data-testid="template-picker-button">
      <Button
        data-testid="template-picker-button-el"
        onClick={() => setDisplayMode(DisplayMode.TemplatePicker)}
        leadingVisual={RepoIcon}
        trailingVisual={PencilIcon}
        ref={templatePickerButtonRef}
      >
        {data && (
          <span>
            {templateText} <Text sx={{fontWeight: 'light'}}>in</Text> {data.nameWithOwner}
          </span>
        )}
        {!repository && <>Select a repository</>}
      </Button>
    </Box>
  )
}
