import {FormControl, TextInput} from '@primer/react'
import {z} from 'zod/v4'

import {getFormValidationNode} from '../../helpers/Validation'
import type {ProviderFieldProps} from './ProvidersFields'

export const azureFormSchema = {
  provider: z.literal('azureai'),
  // TODO: We should validate this url more thoroughly
  deployment_url: z.string().nonempty('A deployment URL is required'),
  model_id: z.string().nonempty('A model ID is required'),
} as const

export function AzureAIFields({validation, isPending}: ProviderFieldProps) {
  return (
    <>
      <FormControl required disabled={isPending}>
        <FormControl.Label>Deployment URL</FormControl.Label>
        <TextInput name="deployment_url" data-1p-ignore className="width-full" autoComplete="off" />
        {getFormValidationNode(validation?.deployment_url)}
      </FormControl>
      <FormControl required disabled={isPending}>
        <FormControl.Label>Model ID</FormControl.Label>
        <TextInput name="model_id" data-1p-ignore className="width-full" autoComplete="off" />
        {getFormValidationNode(validation?.model_id)}
      </FormControl>
    </>
  )
}
