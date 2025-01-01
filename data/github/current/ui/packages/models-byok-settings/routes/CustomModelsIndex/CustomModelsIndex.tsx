import {useRouteQuery} from '@github-ui/react-core/future/use-route-query'
import {getQueryClient} from '@github-ui/react-core/query-client'
import {KeyIcon} from '@primer/octicons-react'
import {PageHeader, Stack, UnderlineNav} from '@primer/react'
import {Blankslate} from '@primer/react/experimental'
import {useCallback, useState} from 'react'

import {AddCustomKeyButton} from '../../components/AddCustomKeyButton'
import {ApiKeys} from '../../components/ApiKeys'
import {AvailableModels} from '../../components/AvailableModels'
import {CurrentOrgProvider} from '../../contexts/CurrentOrgContext'
import {PageBannerOutlet} from '../../contexts/PageBannerContext'
import type {CustomModelsIndexTabs} from '../../types'
import {customModelsIndexRoute} from './custom-models-index-route'
import {useUpdateCustomModel} from './use-update-custom-model'

export function CustomModelsIndex() {
  const {data} = useRouteQuery(customModelsIndexRoute, 'mainQuery')

  const hasKeys = data.customKeys.length > 0

  return (
    <CurrentOrgProvider value={data.orgDisplayLogin}>
      <PageBannerOutlet />
      <Stack gap="spacious">
        <PageHeader hasBorder>
          <PageHeader.TitleArea>
            <PageHeader.Title as="h2" className="text-light">
              Custom models
            </PageHeader.Title>
          </PageHeader.TitleArea>
          {hasKeys && (
            <PageHeader.Actions>
              <AddCustomKeyButtonShowRoute />
            </PageHeader.Actions>
          )}
        </PageHeader>
        <p>
          Add external API keys to enable custom models. Once added, you can select which features a custom model will
          be available for.
        </p>
        {hasKeys ? <CustomKeysTabs /> : <EmptyState />}
      </Stack>
    </CurrentOrgProvider>
  )
}

function CustomKeysTabs() {
  const {
    data: {customModels, customKeys},
  } = useRouteQuery(customModelsIndexRoute, 'mainQuery')

  const [selectedTab, setSelectedTab] = useState<CustomModelsIndexTabs>('keys')

  const customModelsCount = customModels.length
  const keyCount = customKeys.length

  const ariaCurrent = (tab: CustomModelsIndexTabs): {'aria-current'?: 'page'} =>
    selectedTab === tab ? {'aria-current': 'page'} : {}

  const {mutateAsync: updateModel} = useUpdateCustomModel()

  return (
    <div className="border rounded-2">
      <UnderlineNav aria-label="Custom models navigation">
        <UnderlineNav.Item
          onClick={() => setSelectedTab('keys')}
          counter={keyCount}
          as="button"
          {...ariaCurrent('keys')}
        >
          API Keys
        </UnderlineNav.Item>
        <UnderlineNav.Item
          onClick={() => setSelectedTab('models')}
          counter={customModelsCount}
          as="button"
          {...ariaCurrent('models')}
        >
          Custom Models
        </UnderlineNav.Item>
      </UnderlineNav>
      <Stack gap="none">
        {selectedTab === 'keys' ? (
          <ApiKeys customKeys={customKeys} />
        ) : (
          <AvailableModels customKeys={customKeys} customModels={customModels} updateModel={updateModel} />
        )}
      </Stack>
    </div>
  )
}

function AddCustomKeyButtonShowRoute() {
  const {
    data: {publicKey},
    queryKey,
  } = useRouteQuery(customModelsIndexRoute, 'mainQuery')

  const onSuccess = useCallback(() => {
    void getQueryClient().invalidateQueries({queryKey})
  }, [queryKey])

  return <AddCustomKeyButton onSuccess={onSuccess} publicKey={publicKey[1]} />
}

function EmptyState() {
  return (
    <Blankslate data-hpc>
      <Blankslate.Visual>
        <KeyIcon size="small" />
      </Blankslate.Visual>
      <Blankslate.Heading>No custom keys added</Blankslate.Heading>
      <Blankslate.Description>
        Import and manage API keys to enable custom AI models for your organization
      </Blankslate.Description>
      <div className="mt-3">
        <AddCustomKeyButtonShowRoute />
      </div>
    </Blankslate>
  )
}
