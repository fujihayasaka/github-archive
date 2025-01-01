import {RepositoryPickerInternal} from '@github-ui/item-picker/RepositoryPicker'
import type {RepositoryPickerTopRepositoriesQuery$data} from '@github-ui/item-picker/RepositoryPickerTopRepositoriesQuery.graphql'

export type CopilotWorkspaceRepositoryPickerProps = {
  isOpen: boolean
  anchorRef: React.RefObject<HTMLElement>
  topRepos: RepositoryPickerTopRepositoriesQuery$data | null
  onSelect: (repo: {id: string; name: string; owner: {login: string}}) => void
  onClose: () => void
}

export const CopilotWorkspaceRepositoryPicker = ({
  isOpen,
  anchorRef,
  topRepos,
  onSelect,
  onClose,
}: CopilotWorkspaceRepositoryPickerProps) => {
  return (
    <RepositoryPickerInternal
      initialRepository={undefined}
      onSelect={repo => {
        if (repo?.owner && repo?.name) {
          onSelect({
            id: repo.id,
            name: repo.name,
            owner: {login: repo.owner.login},
          })
        }
      }}
      topRepositoriesData={topRepos?.viewer || null}
      anchorElement={props => {
        const {ref} = props as React.HTMLAttributes<HTMLButtonElement> & {
          ref: React.MutableRefObject<HTMLButtonElement | null>
        }
        if (ref) {
          ref.current = anchorRef.current as HTMLButtonElement | null
        }
        return <></>
      }}
      preventDefault
      title="Select a repository"
      subtitle="Start a Codespace with Copilot Agent Mode for this issue in another repository."
      triggerOpen={isOpen}
      onClose={onClose}
    />
  )
}
