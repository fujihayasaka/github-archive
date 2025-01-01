import {FormControl, Stack} from '@primer/react'
import {z} from 'zod/v4'

import {getFormValidationNode} from '../../helpers/Validation'
import styles from '../AddEditDialog.module.css'
import {ModelSelectorPane} from '../ModelSelectorPane'
import type {ProviderFieldProps} from './ProvidersFields'

export const openaiFormSchema = {
  provider: z.literal('openai'),
  models: z.array(
    z.object({
      slug: z.string(),
      name: z.string().nullish(),
    }),
    'Please select a model',
  ),
} as const

export function OpenAIFields({validation, isPending}: ProviderFieldProps) {
  return (
    <Stack.Item grow className={styles.ModelSelectorLayout}>
      <FormControl className="width-full" disabled={isPending}>
        <FormControl.Label>Available models</FormControl.Label>
        <ModelSelectorPane models={[]} selected={[]} />
        {getFormValidationNode(validation?.models)}
      </FormControl>
    </Stack.Item>
  )
}
