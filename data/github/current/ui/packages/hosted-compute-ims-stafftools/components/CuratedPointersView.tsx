import {Table} from '@primer/react/experimental'
import {CuratedPointersTable} from './CuratedPointersTable'
import {tableGapStyle} from '../helpers/style'
import type {ImageDefinition, OwnerId} from '../types/types'
import {Box, Button} from '@primer/react'
import {useEffect, useState} from 'react'
import {NewEditCuratedImagePointerDialog} from './NewEditCuratedImagePointerDialog'

interface CuratedPointersViewProps {
  pointerImages: ImageDefinition[]
  curatedImages: ImageDefinition[]
}

export function CuratedPointersView(props: CuratedPointersViewProps) {
  const [showCreateImagePointerDialog, setShowCreateImagePointerDialog] = useState<boolean>(false)
  const [createImagePointerOwnerId, setCreateImagePointerOwnerId] = useState<OwnerId>('github')

  const openCreateImagePointerDialog = (ownerId: OwnerId) => {
    setCreateImagePointerOwnerId(ownerId)
    setShowCreateImagePointerDialog(true)
  }

  const pointerGitHubImages = props.pointerImages.filter(x => x.ownerId === 'github')
  const pointerGitHubImagesCount = pointerGitHubImages.length
  const pointerPartnerImages = props.pointerImages.filter(x => x.ownerId === 'partner')
  const pointerPartnerImagesCount = pointerPartnerImages.length

  useEffect(() => {
    window.scrollTo(0, 0)
  }, [])

  return (
    <Box sx={tableGapStyle}>
      <div>
        <Table.Container>
          <Table.Title as="h2" id="pointers">
            Pointers for GitHub images ({pointerGitHubImagesCount})
          </Table.Title>
          <Table.Actions>
            <Button onClick={() => openCreateImagePointerDialog('github')} disabled={props.curatedImages.length <= 0}>
              New pointer
            </Button>
          </Table.Actions>
          {pointerGitHubImagesCount > 0 && (
            <CuratedPointersTable pointerImages={pointerGitHubImages} curatedImages={props.curatedImages} />
          )}
        </Table.Container>
      </div>
      <div>
        <Table.Container>
          <Table.Title as="h2" id="pointers">
            Pointers for Partner images ({pointerPartnerImagesCount})
          </Table.Title>
          <Table.Actions>
            <Button onClick={() => openCreateImagePointerDialog('partner')} disabled={props.curatedImages.length <= 0}>
              New pointer
            </Button>
          </Table.Actions>
          {pointerPartnerImagesCount > 0 && (
            <CuratedPointersTable pointerImages={pointerPartnerImages} curatedImages={props.curatedImages} />
          )}
        </Table.Container>
      </div>
      {showCreateImagePointerDialog && (
        <NewEditCuratedImagePointerDialog
          closeDialog={() => setShowCreateImagePointerDialog(false)}
          referencedImagesCandidates={props.curatedImages}
          pointerOwner={createImagePointerOwnerId}
        />
      )}
    </Box>
  )
}
