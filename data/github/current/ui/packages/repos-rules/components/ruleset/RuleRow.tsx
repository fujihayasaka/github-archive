import type {FC, RefObject} from 'react'
import {useMemo, useState} from 'react'
import {FormControl, Checkbox, Label, Box, Button, Text} from '@primer/react'
import {ChevronDownIcon, ChevronUpIcon} from '@primer/octicons-react'
import {BetaLabel} from '@github-ui/lifecycle-labels/beta'
import type {
  Rule,
  RuleSchema,
  ValidationError,
  HelpUrls,
  Parameter,
  RuleConfigMetadata,
  SourceType,
  RegisteredRuleErrorComponent,
  FieldRef,
  RegisteredRuleSchemaComponent,
} from '../../types/rules-types'
import {componentRegistry, defaultRegistry, errorRegistry, visibilityRegistry} from '../rule-schema'
import {RulesetError} from '../rule-schema/errors/RulesetError'
import {isFeatureEnabled} from '@github-ui/feature-flags'

type RuleRowProps = {
  readOnly: boolean
  rulesetId?: number
  sourceType: SourceType
  rule?: Rule
  ruleSchema: RuleSchema
  errors: ValidationError[]
  errorRef?: RefObject<HTMLDivElement>
  fieldRefs?: FieldRef
  helpUrls?: HelpUrls
  onAdd: () => void
  onRemove: () => void
  onUpdateParameters: (parameters: Parameter) => void
}

export const RuleRow: FC<RuleRowProps> = ({
  readOnly,
  rulesetId,
  sourceType,
  rule,
  ruleSchema,
  errors,
  errorRef,
  fieldRefs,
  helpUrls,
  onAdd,
  onUpdateParameters,
  onRemove,
}) => {
  const [additionalOptionsExpanded, setAdditionalOptionsExpanded] = useState(false)

  const ErrorComponent: React.FC<RegisteredRuleErrorComponent> | undefined =
    rule?.ruleType && errors.length > 0
      ? errorRegistry[rule.ruleType] || ((props: RegisteredRuleErrorComponent) => <RulesetError {...props} />)
      : undefined

  const fields = !readOnly
    ? ruleSchema.parameterSchema.fields
    : ruleSchema.parameterSchema.fields.filter(
        field =>
          // defer to visibility registery if defined
          (field.ui_control && visibilityRegistry[field.ui_control]?.(rule?.parameters[field.name], readOnly)) ??
          (field.type !== 'boolean' || (rule?.parameters[field.name] as boolean) === true),
      )
  const hideContainer = ruleSchema.parameterSchema.ui_options?.hide_settings_container || false

  const renderErrorComponent = useMemo(() => {
    // No errors, no component to render
    if (errors.length === 0) {
      return false
    }
    // Rule is disabled don't show the error
    if (rule === undefined) {
      return false
    }

    return true
  }, [errors.length, rule])
  const enabled = isFeatureEnabled('lifecycle_label_name_updates')

  return (
    <div className={`d-flex flex-1 flex-column`}>
      {!readOnly ? (
        <FormControl>
          <Checkbox
            checked={typeof rule !== 'undefined'}
            aria-errormessage={`${rule?.ruleType}-error`}
            aria-invalid={renderErrorComponent && !!ErrorComponent}
            onChange={e => {
              if (e.target.checked) {
                setAdditionalOptionsExpanded(true)
                onAdd()
              } else {
                onRemove()
              }
            }}
          />
          {ruleSchema.beta ? (
            <FormControl.Label sx={{display: 'flex', justifyContent: 'center'}}>
              {ruleSchema.displayName}
              {enabled ? (
                <BetaLabel className="ml-2" />
              ) : (
                <Label variant="success" sx={{marginLeft: 2}}>
                  Beta
                </Label>
              )}
            </FormControl.Label>
          ) : (
            <FormControl.Label>{ruleSchema.displayName}</FormControl.Label>
          )}
          <FormControl.Caption>{ruleSchema.description}</FormControl.Caption>
        </FormControl>
      ) : (
        <div>
          {ruleSchema.beta ? (
            <span className="d-flex flex-items-center text-bold">
              {ruleSchema.displayName}
              {enabled ? (
                <BetaLabel className="ml-2" />
              ) : (
                <Label variant="success" sx={{marginLeft: 2}}>
                  Beta
                </Label>
              )}
            </span>
          ) : (
            <span className="text-bold">{ruleSchema.displayName}</span>
          )}
          <span className="d-block text-small color-fg-muted">{ruleSchema.description}</span>
        </div>
      )}

      {renderErrorComponent && ErrorComponent ? (
        <div className="flex-1">
          <Box sx={{pl: 2}}>
            <Box sx={{px: 3}}>
              <ErrorComponent
                errorId={`${rule?.ruleType}-error`}
                rulesetId={rulesetId}
                errors={errors}
                sourceType={sourceType}
                errorRef={errorRef}
                fields={fields}
              />
            </Box>
          </Box>
        </div>
      ) : null}

      {rule && fields.length > 0 && (
        <>
          {hideContainer ? (
            <div className="flex-1 mt-2">
              <Box sx={{pl: `${readOnly ? '-2px' : '2'}`}}>
                <AdditionalSettings
                  readOnly={readOnly}
                  rulesetId={rulesetId}
                  sourceType={sourceType}
                  helpUrls={helpUrls}
                  fields={fields}
                  fieldRefs={fieldRefs}
                  errors={errors || []}
                  parameters={rule.parameters}
                  metadata={rule.metadata}
                  onParametersChange={onUpdateParameters}
                />
              </Box>
            </div>
          ) : (
            <div className="flex-1 mt-2">
              <Box sx={{pl: `${readOnly ? '0' : '12px'}`}}>
                <Button
                  variant="invisible"
                  sx={{color: 'fg.subtle'}}
                  onClick={() => setAdditionalOptionsExpanded(prev => !prev)}
                >
                  <Text sx={{mr: 1}}>
                    {additionalOptionsExpanded ? 'Hide additional settings' : 'Show additional settings'}
                  </Text>
                  {additionalOptionsExpanded ? <ChevronUpIcon /> : <ChevronDownIcon />}
                </Button>
              </Box>
              {additionalOptionsExpanded && (
                <Box sx={{pl: `${readOnly ? '-2px' : '10px'}`}}>
                  <AdditionalSettings
                    readOnly={readOnly}
                    rulesetId={rulesetId}
                    sourceType={sourceType}
                    helpUrls={helpUrls}
                    fields={fields}
                    errors={errors || []}
                    fieldRefs={fieldRefs}
                    parameters={rule.parameters}
                    metadata={rule.metadata}
                    onParametersChange={onUpdateParameters}
                  />
                </Box>
              )}
            </div>
          )}
        </>
      )}
    </div>
  )
}

const AdditionalSettings = ({
  readOnly,
  rulesetId,
  sourceType,
  fields,
  errors,
  fieldRefs,
  parameters,
  metadata,
  helpUrls,
  onParametersChange,
}: Pick<RuleRowProps, 'readOnly' | 'rulesetId' | 'sourceType' | 'helpUrls'> & {
  fields: RuleSchema['parameterSchema']['fields']
  fieldRefs?: FieldRef
  errors: ValidationError[]
  parameters: Parameter
  metadata?: RuleConfigMetadata
  onParametersChange: (paramters: Parameter) => void
}) => (
  <ul>
    {fields.map(field => {
      const fieldErrors = errors.filter(error => error.field === field.name)

      let RegisteredComponent: FC<RegisteredRuleSchemaComponent> | undefined = undefined
      if (field.ui_control) {
        RegisteredComponent = componentRegistry[field.ui_control]
        if (!RegisteredComponent) {
          throw new Error(`Unsupported control: ${field.ui_control}`)
        }
      } else {
        RegisteredComponent = defaultRegistry[field.type]
        if (!RegisteredComponent) {
          throw new Error(`Field type requires custom control: ${JSON.stringify(field)}`)
        }
      }

      return (
        <li key={field.name} className="px-3 py-2 d-flex flex-column">
          <RegisteredComponent
            readOnly={readOnly}
            rulesetId={rulesetId}
            sourceType={sourceType}
            helpUrls={helpUrls}
            field={field}
            fieldRef={fieldRefs?.[field.name]}
            value={parameters[field.name]}
            metadata={metadata}
            errors={fieldErrors}
            onValueChange={newValue =>
              onParametersChange({
                ...parameters,
                [field.name]: newValue,
              })
            }
          />
        </li>
      )
    })}
  </ul>
)
