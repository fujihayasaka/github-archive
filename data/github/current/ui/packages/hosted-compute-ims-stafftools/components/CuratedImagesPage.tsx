import {Blankslate, Table} from '@primer/react/experimental'
import {CuratedImagesPointerTable} from './CuratedImagesPointerTable'
import {CuratedImagesTable} from './CuratedImagesTable'
import {tableGapStyle} from '../helpers/style'
import type {ImageDefinition} from '../types/types'
import {Box, Button} from '@primer/react'
import {CuratedImagePointersTableConstants, CuratedImagesTableConstants} from '../helpers/constants'
import {useEffect, useState} from 'react'
import {NewEditCuratedImagePointerDialog} from './NewEditCuratedImagePointerDialog'
import {NewEditCuratedImageDialog} from './NewEditCuratedImageDialog'
import {splitCuratedImageDefinitions} from '../helpers/utils'

interface CuratedImagesPageProps {
  imageDefinitions: ImageDefinition[]
}

export function CuratedImagesPage(props: CuratedImagesPageProps) {
  const [showCreateImagePointerDialog, setShowCreateImagePointerDialog] = useState<boolean>(false)
  const [showCreateImageDialog, setShowCreateImageDialog] = useState<boolean>(false)

  const {imageDefinitionsList, imagePointersList} = splitCuratedImageDefinitions(props.imageDefinitions)

  const imageDefinitionPointersCount = imagePointersList.length
  const imageDefinitionsCount = imageDefinitionsList.length

  useEffect(() => {
    window.scrollTo(0, 0)
  }, [])

  return (
    <Box sx={tableGapStyle}>
      <div>
        <Table.Container>
          <Table.Title as="h2" id="pointers">
            {CuratedImagePointersTableConstants.tableTitle}
          </Table.Title>
          <Table.Actions>
            <Button onClick={() => setShowCreateImagePointerDialog(true)} disabled={imageDefinitionsCount <= 0}>
              {CuratedImagePointersTableConstants.newAction}
            </Button>
          </Table.Actions>
          {imageDefinitionPointersCount > 0 && <CuratedImagesPointerTable imageDefinitions={props.imageDefinitions} />}
        </Table.Container>
        {imageDefinitionPointersCount === 0 && (
          <Box sx={{pt: 2}}>
            <Blankslate border>
              <Blankslate.Heading>{CuratedImagePointersTableConstants.blankStateTitle}</Blankslate.Heading>
              <Blankslate.Description>{CuratedImagePointersTableConstants.blankStateSubtitle}</Blankslate.Description>
            </Blankslate>
          </Box>
        )}
      </div>
      <div>
        <Table.Container>
          <Table.Title as="h2" id="curated-images">
            {CuratedImagesTableConstants.tableTitle}
          </Table.Title>
          <Table.Actions>
            <Button onClick={() => setShowCreateImageDialog(true)}>{CuratedImagesTableConstants.newAction}</Button>
          </Table.Actions>
          {imageDefinitionsCount > 0 && <CuratedImagesTable imageDefinitions={props.imageDefinitions} />}
        </Table.Container>
        {imageDefinitionsCount === 0 && (
          <Box sx={{pt: 2}}>
            <Blankslate border>
              <Blankslate.Heading>{CuratedImagesTableConstants.blankStateTitle}</Blankslate.Heading>
              <Blankslate.Description>{CuratedImagesTableConstants.blankStateSubtitle}</Blankslate.Description>
            </Blankslate>
          </Box>
        )}
      </div>
      {showCreateImagePointerDialog && (
        <NewEditCuratedImagePointerDialog
          closeDialog={() => setShowCreateImagePointerDialog(false)}
          imageDefinitions={props.imageDefinitions}
        />
      )}
      {showCreateImageDialog && <NewEditCuratedImageDialog closeDialog={() => setShowCreateImageDialog(false)} />}
    </Box>
  )
}
