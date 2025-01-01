import {AnalyticsProvider} from '@github-ui/analytics-provider'
import {noop} from '@github-ui/noop'
import {PartialEntry} from '@github-ui/react-core/partial-entry'
import {relayEnvironmentWithMissingFieldHandlerForNode} from '@github-ui/relay-environment'
import type {History} from '@remix-run/router'
import {useEffect, useMemo, useState, type Key} from 'react'
import type {Root} from 'react-dom/client'
import {RelayEnvironmentProvider} from 'react-relay'
import {VALUES} from '../constants/values'
import {getSafeConfig} from '../utils/option-config'
import {CreateIssueDialogEntry} from './CreateIssueDialogEntry'

export function renderCreateDialogPartialEntry(
  root: Root,
  {history, key, ...props}: CreateIssueModalProps & {history: History; key: Key},
) {
  root.render(
    <PartialEntry
      key={key}
      partialName="issue-create"
      embeddedData={{
        props,
      }}
      Component={WrapperComponent}
      wasServerRendered={false}
      history={history}
    />,
  )
}

const environment = relayEnvironmentWithMissingFieldHandlerForNode()

function WrapperComponent(props: CreateIssueModalProps) {
  return (
    <RelayEnvironmentProvider environment={environment}>
      <AnalyticsProvider
        appName={props.analyticsAppName ?? 'UNKNOWN'}
        category={props.analyticsNamespace ?? 'issue-create-web-component'}
        metadata={{}}
      >
        <CreateIssueModal {...props} />
      </AnalyticsProvider>
    </RelayEnvironmentProvider>
  )
}

export type CreateIssueModalProps = {
  owner?: string
  repository?: string
  analyticsAppName?: string
  analyticsNamespace?: string
}

export function CreateIssueModal({owner, repository}: CreateIssueModalProps) {
  const [isVisible, setIsVisible] = useState(true)

  useEffect(() => {
    setIsVisible(true)
  }, [])

  const repo = useMemo(
    () =>
      owner && repository
        ? {
            repository: {
              owner,
              name: repository,
            },
          }
        : undefined,
    [owner, repository],
  )

  if (!isVisible) return null

  // TODO: setup real value for the config below
  return (
    <CreateIssueDialogEntry
      navigate={noop}
      isCreateDialogOpen={isVisible}
      setIsCreateDialogOpen={setIsVisible}
      optionConfig={getSafeConfig({
        storageKeyPrefix: VALUES.storageKeyPrefixes.globalAdd,
        pasteUrlsAsPlainText: false,
        singleKeyShortcutsEnabled: true,
        useMonospaceFont: false,
        issueCreateArguments: repo,
        showFullScreenButton: false,
      })}
    />
  )
}
