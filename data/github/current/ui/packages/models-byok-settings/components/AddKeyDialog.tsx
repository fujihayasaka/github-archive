import {encrypt} from '@github-ui/encryption'
import {encode} from '@github-ui/encryption/utils'
import {ResponseError} from '@github-ui/react-core/future/response-error'
import {useMutation} from '@github-ui/react-query'
import {reactFetchJSON} from '@github-ui/verified-fetch'
import {Dialog, FormControl, Stack, TextInput} from '@primer/react'
import {Banner} from '@primer/react/experimental'
import {type FormEvent, type RefObject, startTransition, useId, useMemo, useState} from 'react'
import {z} from 'zod/v4'

import {useCurrentOrg} from '../contexts/CurrentOrgContext'
import {getErrorMessageFromResponse} from '../helpers/extract-errors'
import {
  getFormValidationNode,
  getTrailingVisualIcon,
  type ValidationKind,
  validationKindFromZodError,
} from '../helpers/Validation'
import {customModelsIndexRoute} from '../routes/CustomModelsIndex/custom-models-index-route'
import type {CustomModelsIndexMutationData, Provider} from '../types'
import styles from './AddEditDialog.module.css'
import {ProviderPicker} from './ProviderPicker'
import {providerFields, providerList, providerSchema} from './providers/Providers'

const base = z.object({
  provider: z.string().nonempty('A provider must be selected'),
  name: z.string().nonempty('A name is required'),
  api_key: z.string().nonempty('An API key is required'),
})

const formSchema = z.discriminatedUnion('provider', [base.extend(providerSchema[0]), base.extend(providerSchema[1])])

export function AddKeyDialog({
  publicKey,
  anchorRef,
  onCancel,
  onSuccess,
}: {
  publicKey: string
  anchorRef?: RefObject<HTMLElement>
  onCancel: () => void
  onSuccess: (data: CustomModelsIndexMutationData) => void
}) {
  const id = useId()

  const [selectedProvider, setSelectProvider] = useState<Provider>(providerList[0])
  const [validation, setValidation] = useState<Record<string, ValidationKind>>()

  const org = useCurrentOrg()

  const {mutate, isPending} = useMutation<CustomModelsIndexMutationData, ResponseError, z.infer<typeof formSchema>>({
    async mutationFn(variables) {
      const encryptedKey = await encrypt(publicKey, variables.api_key)
      variables.api_key = encode(encryptedKey)

      const r = await reactFetchJSON(customModelsIndexRoute.generatePath({org}), {
        method: 'POST',
        body: variables,
      })
      if (!r.ok) {
        throw new ResponseError('Failed to add custom key', r)
      }
      return r.json() as Promise<CustomModelsIndexMutationData>
    },
  })

  function onSubmitHandler(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()

    const formData = new FormData(event.currentTarget)
    const payload = Object.fromEntries(formData.entries()) as Record<string, unknown>
    payload.models = [] // TODO: Selected models

    const {success, data, error} = formSchema.safeParse(payload)
    if (!success) {
      setValidation(validationKindFromZodError(error))
      return
    }

    startTransition(() => {
      setValidation(undefined)
      mutate(data, {
        onSuccess,
        async onError(mutationError) {
          const message = await getErrorMessageFromResponse(mutationError)

          setValidation({
            __general: {error: message || 'An unexpected error occurred. Please try again later.'},
          })
        },
      })
    })
  }

  const ProviderFields = useMemo(() => {
    return providerFields[selectedProvider.key]
  }, [selectedProvider.key])

  return (
    <Dialog
      title="Add custom key"
      onClose={onCancel}
      position="right"
      width="large"
      className={styles.AddEditDialogLayout}
      returnFocusRef={anchorRef}
      footerButtons={[
        {content: 'Cancel', buttonType: 'default', onClick: onCancel},
        {
          content: 'Save',
          buttonType: 'primary',
          type: 'submit',
          form: `${id}-form`,
          loading: isPending,
          loadingAnnouncement: 'Adding custom key',
        },
      ]}
    >
      <Stack
        as="form"
        id={`${id}-form`}
        className="height-full"
        onSubmit={onSubmitHandler as unknown as React.FormEventHandler<HTMLDivElement>}
      >
        {validation?.__general && (
          <Banner role="banner" title="Error" variant="critical" hideTitle description={validation.__general.error} />
        )}

        <FormControl id={`${id}-provider`} disabled={isPending}>
          <ProviderPicker
            id={`${id}-provider`}
            providers={providerList}
            selected={selectedProvider}
            onSelected={setSelectProvider}
            disabled={isPending}
          />
          <FormControl.Label>Provider</FormControl.Label>
          <input type="hidden" name="provider" value={selectedProvider.key} />
        </FormControl>

        <FormControl required disabled={isPending}>
          <FormControl.Label>Name</FormControl.Label>
          <TextInput
            name="name"
            data-1p-ignore
            placeholder={getNamePlaceholder(`${selectedProvider.name} custom key`)}
            className="width-full"
            autoComplete="off"
          />
          {getFormValidationNode(validation?.name)}
          <FormControl.Caption>Models provided will be available under this key</FormControl.Caption>
        </FormControl>

        <FormControl required disabled={isPending}>
          <FormControl.Label>Key</FormControl.Label>
          <TextInput
            name="api_key"
            data-1p-ignore
            type="password"
            autoComplete="new-password"
            className="width-full"
            trailingVisual={getTrailingVisualIcon(validation?.api_key)}
          />
          {getFormValidationNode(validation?.api_key)}
        </FormControl>

        <ProviderFields validation={validation} isPending={isPending} />
      </Stack>
    </Dialog>
  )
}

function getNamePlaceholder(label: string) {
  return label.toLowerCase().replaceAll(/ /g, '_')
}
