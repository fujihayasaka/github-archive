import {AlertIcon, CheckIcon} from '@primer/octicons-react'
import {FormControl} from '@primer/react'
import z from 'zod/v4'

import styles from './Validation.module.css'

export type ValidationKind = {error?: string; success?: string}

export function validationKindFromZodError(error: z.ZodError): Record<string, ValidationKind> {
  const errors = z.treeifyError(error) as {properties?: Record<string, {errors?: string[]}>}

  if (!errors.properties) return {}

  const result: Record<string, ValidationKind> = {}
  for (const key in errors.properties) {
    result[key] = {error: errors.properties[key]?.errors?.[0]}
  }
  return result
}

export function getTrailingVisualIcon(item: ValidationKind | undefined) {
  if (!item) return null
  if ('error' in item) return <AlertIcon fill="var(--fgColor-danger) !important" />
  if ('success' in item) return <CheckIcon fill="var(--fgColor-success) !important" />
  return null
}

export function getFormValidationNode(item: ValidationKind | undefined) {
  if (!item) return null
  let variant: 'success' | 'error' | null = null
  if ('success' in item) variant = 'success'
  if ('error' in item) variant = 'error'
  if (!variant) return null
  return (
    <div className={styles.Validation}>
      <FormControl.Validation variant={variant}>{item[variant]}</FormControl.Validation>
    </div>
  )
}
