import type {PropertyDefinition, PropertyValue} from '@github-ui/custom-properties-types'
import {ShieldLockIcon} from '@primer/octicons-react'
import {Box, FormControl, Stack} from '@primer/react'
import {useFeatureFlag} from '@primer/react/experimental'
import {clsx} from 'clsx'
import {forwardRef, type ReactNode, useEffect, useImperativeHandle, useMemo, useRef} from 'react'

import {CustomPropertyInput} from './CustomPropertyInput'
import {type EditTableProps, ResetDropdown} from './CustomPropertyValuesTable'
import styles from './CustomPropertyValuesTableV2.module.css'

interface CustomPropertyValuesTableV2Props extends EditTableProps {
  showSummary: boolean
}

export const CustomPropertyValuesTableV2 = forwardRef((props: CustomPropertyValuesTableV2Props, ref) => {
  const {definitions, propertyValuesMap, orgName, showUndo = true, showSummary} = props

  const {editableDefinitions} = props as EditTableProps
  const editableDefinitionsSet = useMemo(
    () => new Set((editableDefinitions || []).map((definition: PropertyDefinition) => definition.propertyName)),
    [editableDefinitions],
  )

  const {refsByPropertyName, setRef, clearRefs} = usePropertyInputRefs()

  useEffect(() => {
    clearRefs()
  }, [clearRefs, editableDefinitionsSet])

  useImperativeHandle(ref, () => ({
    focusInput: (propertyName: string) => {
      refsByPropertyName[propertyName]?.focus()
    },
  }))

  if (definitions.length === 0) {
    return null
  }

  return (
    <div>
      {definitions.map(definition => {
        const {propertyName} = definition
        const field = propertyValuesMap[propertyName]
        const isEditable = 'editableDefinitions' in props && editableDefinitionsSet.has(propertyName)

        return (
          <div
            data-testid="property-row"
            key={propertyName}
            className={clsx(styles.propertyRow, showSummary ? styles.readRow : styles.editRow)}
          >
            {showSummary ? (
              <>
                <span className="text-bold fgColor-default mr-2">{`${propertyName}:`}</span>
                <span className="fgColor-muted">{getReadOnlyValue(definition, field?.value)}</span>
              </>
            ) : isEditable ? (
              <CustomPropertyEditValueRowV2
                ref={element => {
                  setRef(propertyName, element)
                }}
                key={propertyName}
                changed={!!field?.changed}
                mixed={!!field?.mixed}
                propertyValue={field?.value}
                definition={definition}
                error={field?.error}
                onChange={newValue => props.setPropertyValue(propertyName, newValue)}
                onReset={() => props.revertPropertyValue(propertyName)}
                showUndo={showUndo}
                orgName={orgName}
              />
            ) : (
              <CustomPropertyReadValueRowV2 key={propertyName} propertyValue={field?.value} definition={definition} />
            )}
          </div>
        )
      })}
    </div>
  )
})

CustomPropertyValuesTableV2.displayName = 'CustomPropertyValuesTableV2'

const CustomPropertyEditValueRowV2 = forwardRef(
  (
    {
      propertyValue,
      definition,
      changed,
      mixed = false,
      error,
      onChange,
      onReset,
      showUndo,
      orgName,
    }: {
      propertyValue?: PropertyValue
      definition: PropertyDefinition
      changed: boolean
      mixed?: boolean
      error?: string
      onChange: (value: PropertyValue) => void
      onReset(): void
      showUndo: boolean
      orgName: string
    },
    ref: React.ForwardedRef<HTMLElement>,
  ) => {
    const {propertyName, description} = definition

    const editingRedesignEnabled = useFeatureFlag('custom_properties_editing_redesign')
    const propertyNameValidationId = `${propertyName}-validation-error`

    return (
      <DataTableRow
        label={propertyName}
        description={description}
        value={
          <>
            <Box sx={{display: 'flex', gap: 2}}>
              <CustomPropertyInput
                ref={ref}
                {...definition}
                propertyValue={propertyValue}
                mixed={mixed}
                onChange={onChange}
                orgName={orgName}
                editingRedesignEnabled={editingRedesignEnabled}
                inputProps={error ? {'aria-describedby': propertyNameValidationId} : {}}
              />
            </Box>
            {error && (
              <FormControl.Validation variant="error" id={propertyNameValidationId} sx={{pt: 2}}>
                {error}
              </FormControl.Validation>
            )}
          </>
        }
        trailing={<ResetDropdown definition={definition} {...{changed, onReset, onChange, showUndo}} />}
      />
    )
  },
)

CustomPropertyEditValueRowV2.displayName = 'CustomPropertyEditValueRowV2'

function CustomPropertyReadValueRowV2({
  propertyValue,
  definition,
}: {
  propertyValue?: PropertyValue
  definition: PropertyDefinition
}) {
  const {description, propertyName} = definition
  const readOnlyValue = getReadOnlyValue(definition, propertyValue)

  return (
    <DataTableRow
      label={propertyName}
      description={description}
      value={
        <Stack direction="horizontal" gap="condensed">
          <Stack.Item className="flex-shrink-0">
            <ShieldLockIcon size="small" />
          </Stack.Item>
          <Stack.Item>
            <span>{readOnlyValue}</span>
          </Stack.Item>
        </Stack>
      }
    />
  )
}

const getCommaSeparatedString = (value: PropertyValue) => (Array.isArray(value) ? value.join(', ') : value)

const getReadOnlyValue = (definition: PropertyDefinition, value?: PropertyValue) => {
  if (value) return value
  if (definition.defaultValue) return `Default (${getCommaSeparatedString(definition.defaultValue)})`
  return ''
}

const formControlStyle = {
  display: 'grid',
  flex: 1,
  py: 3,
  gridTemplateColumns: ['1fr auto', '1fr auto', '1fr 220px minmax(39px, auto)'],
  gridTemplateRows: ['auto auto auto auto', 'auto auto auto auto', '1fr min-content min-content'],
  gridTemplateAreas: [
    '"name trailing" "description trailing" "value trailing" "bottomMessage trailing"',
    '"name trailing" "description trailing" "value trailing" "bottomMessage trailing"',
    '"name value trailing" "description value trailing" "bottomMessage value trailing"',
  ],
}

function DataTableRow({
  label,
  description,
  bottomMessage,
  value,
  trailing,
}: {
  label: string
  description: string | null
  bottomMessage?: ReactNode
  value: ReactNode
  trailing?: ReactNode
}) {
  return (
    <FormControl sx={formControlStyle}>
      <FormControl.Label
        sx={{
          gridArea: 'name',
          pr: 3,
          whiteSpace: 'nowrap',
          overflow: 'hidden',
          textOverflow: 'ellipsis',
          alignSelf: 'center',
        }}
        data-testid="property-name"
      >
        {label}
      </FormControl.Label>

      <Box sx={{gridArea: 'value', mt: [1, 1, 0]}}>{value}</Box>

      {trailing ? <Box sx={{gridArea: 'trailing', pl: 2, mt: 0}}>{trailing}</Box> : null}

      {description && (
        <FormControl.Caption sx={{gridArea: 'description', pr: 3, mt: 0}}>{description}</FormControl.Caption>
      )}
      {bottomMessage ? <Box sx={{gridArea: 'bottomMessage', mt: 1}}>{bottomMessage}</Box> : null}
    </FormControl>
  )
}

export interface CustomPropertyValuesTableRef {
  focusInput: (propertyName: string) => void
}

const usePropertyInputRefs = () => {
  const refsByName = useRef<Record<string, HTMLElement | null>>({})

  const setRef = (propertyName: string, element: HTMLElement | null) => {
    refsByName.current[propertyName] = element
  }

  const clearRefs = () => {
    refsByName.current = {}
  }

  return {refsByPropertyName: refsByName.current, setRef, clearRefs}
}
