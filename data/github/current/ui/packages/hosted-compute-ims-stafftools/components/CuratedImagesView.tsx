import {Table} from '@primer/react/experimental'
import {CuratedImagesTable} from './CuratedImagesTable'
import {tableGapStyle} from '../helpers/style'
import type {ImageDefinition, OwnerId} from '../types/types'
import {Box, Button} from '@primer/react'
import {useState} from 'react'
import {NewEditCuratedImageDialog} from './NewEditCuratedImageDialog'

interface CuratedImagesViewProps {
  curatedOwnerId: OwnerId
  curatedImages: ImageDefinition[]
  pointerImages: ImageDefinition[]
}

export function CuratedImagesView(props: CuratedImagesViewProps) {
  const [showCreateImageDialog, setShowCreateImageDialog] = useState<boolean>(false)

  const curatedImagesCount = props.curatedImages.length

  return (
    <Box sx={tableGapStyle}>
      <div>
        <Table.Container>
          <Table.Title as="h2" id="curated-images">
            Images ({curatedImagesCount})
          </Table.Title>
          <Table.Actions>
            <Button onClick={() => setShowCreateImageDialog(true)}>New image</Button>
          </Table.Actions>
          {curatedImagesCount > 0 && (
            <CuratedImagesTable curatedImages={props.curatedImages} pointerImages={props.pointerImages} />
          )}
        </Table.Container>
      </div>
      {showCreateImageDialog && (
        <NewEditCuratedImageDialog
          curatedOwner={props.curatedOwnerId}
          closeDialog={() => setShowCreateImageDialog(false)}
        />
      )}
    </Box>
  )
}
