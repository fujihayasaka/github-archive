import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import type {CustomPropertyDefinitionPayload} from '../types/stafftools-custom-properties-types'
import {CheckIcon, XIcon} from '@primer/octicons-react'
import {Box, Link} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {PageHeader} from '@primer/react/experimental'
import {usePropertySource} from '../hooks/use-property-source'

export function CustomPropertyDefinitionShowPage() {
  const {definition} = useRoutePayload<CustomPropertyDefinitionPayload>()
  const {name, description, required, defaultValue, valueType, allowedValues} = definition

  const {listPath} = usePropertySource()

  return (
    <Box sx={{display: 'flex', flexDirection: 'column', rowGap: 2}}>
      <PageHeader>
        <PageHeader.TitleArea>
          <PageHeader.Title>
            <Box sx={{display: 'flex', gap: 2}}>
              <Link href={listPath}>Custom properties</Link> <span>/</span>
              <span>{name}</span>
            </Box>
          </PageHeader.Title>
        </PageHeader.TitleArea>
      </PageHeader>

      <span>
        <strong>Description:</strong> {description}
      </span>
      <span>
        <strong>Value type:</strong> {valueType}
      </span>
      <span>
        <strong>Required:</strong> <Octicon icon={required ? CheckIcon : XIcon} />
      </span>
      {defaultValue && (
        <span>
          <strong>Default value:</strong> {defaultValue}
        </span>
      )}
      {allowedValues && allowedValues.length > 0 && (
        <div>
          <span>
            <strong>Allowed values:</strong>
          </span>
          <Box sx={{display: 'flex', flexDirection: 'column', ml: 2}}>
            {allowedValues.map((value, index) => (
              // eslint-disable-next-line @eslint-react/no-array-index-key
              <span key={index}>{value}</span>
            ))}
          </Box>
        </div>
      )}
    </Box>
  )
}
