import {Box, useResponsiveValue, Text} from '@primer/react'
import {PlaygroundCard} from './GettingStartedDialog/PlaygroundCard'
import {usePlaygroundState} from '../../../contexts/PlaygroundStateContext'
import ModelsAvatar from '../../../components/ModelsAvatar'
import type {ModelState} from '../../../types'
import {testIdProps} from '@github-ui/test-id-props'

interface Props {
  model: ModelState
  submitMessage: (s: string) => void
}

export default function PlaygroundChatEmptyState({model, submitMessage}: Props) {
  const state = usePlaygroundState()
  const {catalogData, modelInputSchema} = model
  const onComparisonMode = state.models.length > 1

  const MAX_SUGGESTIONS = 3
  const isMobile = useResponsiveValue({narrow: true}, false)
  const iconSize = {narrow: 32, regular: 40, wide: 40}

  return (
    <div className="d-flex height-full flex-column flex-justify-center">
      <div className="d-flex flex-row flex-justify-center pb-3">
        <ModelsAvatar model={catalogData} size={iconSize} />
      </div>
      <Text as="h3" sx={{fontWeight: 'bold', textAlign: 'center', pb: 1, fontSize: [2, 2, 3]}}>
        {catalogData.friendly_name}
      </Text>
      <Text as="p" sx={{color: 'fg.muted', textAlign: 'center', pb: [3, 3, 7], fontSize: 1}}>
        {catalogData.summary}
      </Text>
      {modelInputSchema?.sampleInputs && modelInputSchema.sampleInputs.length > 0 ? (
        <Box {...testIdProps('sample-inputs')} sx={{display: 'flex', justifyContent: 'center'}}>
          <Box
            sx={{
              display: 'flex',
              gap: 3,
              maxWidth: ['100%', '100%', `${MAX_SUGGESTIONS * 240 + 32}px`],
              flexDirection: ['column', 'column', onComparisonMode ? 'column' : 'row'],
              pb: [3, 3, 0],
            }}
          >
            {modelInputSchema.sampleInputs.slice(0, MAX_SUGGESTIONS).map((input, index) => {
              const content =
                input.messages && input?.messages[0] && input.messages[0].content ? input.messages[0].content : null
              if (!content) {
                return null
              }
              return (
                <PlaygroundCard
                  size={isMobile ? 'small' : 'large'}
                  sample={content}
                  // eslint-disable-next-line @eslint-react/no-array-index-key
                  key={index}
                  onClick={() => submitMessage(content)}
                />
              )
            })}
          </Box>
        </Box>
      ) : null}
    </div>
  )
}
