import {Box} from '@primer/react'
import {ListView} from '@github-ui/list-view'
import {ListViewMetadata} from '@github-ui/list-view/ListViewMetadata'
import {Blankslate} from '@primer/react/experimental'
import type {Image} from '@github-ui/github-hosted-runners-settings/types/image'

import CustomImageItem from './CustomImageItem'

interface Props {
  entityLogin: string
  images: Image[]
  isEnterprise: boolean
  searchQuery?: string
  canWriteCustomImages: boolean
}

const boxBorderStyles = {
  borderStyle: 'solid',
  borderColor: 'border.default',
  borderWidth: 1,
}

export default function CustomImagesList({
  entityLogin,
  images,
  isEnterprise,
  searchQuery,
  canWriteCustomImages,
}: Props) {
  const filteredImages = images.filter(
    image => !searchQuery || image.displayName.toLowerCase().includes(searchQuery.toLowerCase()),
  )
  const title = `${images.length} custom ${images.length === 1 ? 'image' : 'images'}`

  return (
    <div data-hpc>
      {!filteredImages || filteredImages.length === 0 ? (
        <Box className="rounded-2" sx={boxBorderStyles}>
          <Blankslate>
            <Blankslate.Heading>
              <span data-testid="no-images-error">There are no custom images available.</span>
            </Blankslate.Heading>
          </Blankslate>
        </Box>
      ) : (
        <Box className="rounded-2" sx={boxBorderStyles}>
          <Box sx={{overflowY: 'auto'}} data-testid="display-images-section">
            <ListView
              metadata={<ListViewMetadata title={<span data-testid="images-count">{title}</span>} />}
              title={title}
              titleHeaderTag="h3"
            >
              {filteredImages.map(image => (
                <CustomImageItem
                  key={image.id}
                  imageDefinitionId={image.id}
                  osType={image.osType}
                  displayName={image.displayName}
                  versionsCount={image.versionsCount}
                  totalVersionsSize={image.totalVersionsSize}
                  latestVersion={image.latestVersion}
                  state={image.state ?? null}
                  entityLogin={entityLogin}
                  isEnterprise={isEnterprise}
                  canWriteCustomImages={canWriteCustomImages}
                />
              ))}
            </ListView>
          </Box>
        </Box>
      )}
    </div>
  )
}
