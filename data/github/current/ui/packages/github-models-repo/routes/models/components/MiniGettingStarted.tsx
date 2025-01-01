import {ActionList, ActionMenu, Button, Spinner} from '@primer/react'
import ModelPicker from '../../prompt/components/ModelPicker'
import {ModelsProvider} from '../../prompt/contexts/ModelsContext'
import {CodeIcon, FoldDownIcon, FoldUpIcon} from '@primer/octicons-react'
import {useFilteredModels} from '../../../hooks/use-filtered-models'
import {useEffect, useMemo, useState} from 'react'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import GettingStartedDialog from '@github-ui/github-models/GettingStartedDialog'
import CodeMirror from '@github-ui/code-mirror'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import type {ModelRepoPromptsAppPayload, RepoModel} from '../../../types'
import styles from './MiniGettingStarted.module.css'
import mainStyles from '../ModelsRoute.module.css'
import {CopyToClipboardButton} from '@github-ui/copy-to-clipboard/Button'
import {useQuery} from '@github-ui/react-query'
import {promptModelIdentifierFor} from '../../prompt/models'

export function MiniGettingStarted({
  showDialog,
  setShowDialog,
}: {
  showDialog: boolean
  setShowDialog: (show: boolean) => void
}) {
  const {repository, restrictedModels} = useAppPayload<ModelRepoPromptsAppPayload>()
  const {availableModels, isLoadingModels} = useFilteredModels(repository.ownerLogin, repository.name, restrictedModels)
  const [selectedModel, setSelectedModel] = useState<RepoModel | undefined>(undefined)
  const [selectedLanguage, setSelectedLanguage] = useState<string | undefined>(undefined)
  const [selectedSdk, setSelectedSdk] = useState<string | undefined>(undefined)
  const [showExpanded, setShowExpanded] = useState(false)

  const {data: gettingStarted} = useQuery({
    queryKey: ['github-models-repos', 'getting-started', repository.ownerLogin, repository.name, selectedModel],
    async queryFn() {
      if (!selectedModel) return {}
      const {registry, name} = selectedModel
      const res = await verifiedFetchJSON(`/${repository.ownerLogin}/${repository.name}/models/${registry}/${name}`)
      if (res.ok) {
        const json = await res.json()
        return json.gettingStarted
      }
      return {}
    },
    initialData: {},
  })

  const languages = useMemo(() => Object.keys(gettingStarted) || [], [gettingStarted])
  const sdks = useMemo(
    () =>
      selectedLanguage && gettingStarted[selectedLanguage]?.sdks
        ? Object.keys(gettingStarted[selectedLanguage].sdks || {})
        : [],
    [gettingStarted, selectedLanguage],
  )

  useEffect(() => {
    if (availableModels.length > 0 && !selectedModel) {
      setSelectedModel(availableModels[0])
    }
  }, [availableModels, selectedModel])

  useEffect(() => {
    if (selectedLanguage && languages.includes(selectedLanguage)) return
    setSelectedLanguage(languages[0])
  }, [languages, selectedLanguage])

  useEffect(() => {
    if (selectedSdk && sdks.includes(selectedSdk)) return
    setSelectedSdk(sdks[0])
  }, [sdks, selectedSdk])

  const codeContent =
    gettingStarted && selectedLanguage && selectedSdk && selectedModel
      ? replaceParameters(gettingStarted[selectedLanguage]?.sdks[selectedSdk]?.codeSamples, selectedModel)
      : undefined

  const isLoading = isLoadingModels || availableModels.length === 0 || !codeContent

  return (
    <>
      <div className="d-flex flex-items-center mt-5 mb-2">
        <div className="flex-1">
          <h2 className={mainStyles.subtitle}>Add AI to your project now</h2>
          <p className={mainStyles.subtext}>Drop this snippet into your code to start using AI instantly.</p>
        </div>
        <Button leadingVisual={CodeIcon} variant="primary" onClick={() => setShowDialog(true)}>
          Get API Key
        </Button>
      </div>
      <div className={`Box rounded-2 ${styles.box}`}>
        <div className={`Box-header ${styles.header}`}>
          {!isLoading && (
            <>
              <div className="d-flex flex-items-center">
                <ModelsProvider models={availableModels}>
                  <ModelPicker selectedModel={selectedModel} onSelect={setSelectedModel} />
                </ModelsProvider>
              </div>
              {gettingStarted && selectedLanguage && (
                <ActionMenu>
                  <ActionMenu.Button>{gettingStarted[selectedLanguage]?.name}</ActionMenu.Button>
                  <ActionMenu.Overlay>
                    <ActionList>
                      {languages.map(language => (
                        <ActionList.Item key={language} onSelect={() => setSelectedLanguage(language)}>
                          {gettingStarted[language]?.name}
                        </ActionList.Item>
                      ))}
                    </ActionList>
                  </ActionMenu.Overlay>
                </ActionMenu>
              )}
              {gettingStarted && selectedLanguage && selectedSdk && (
                <ActionMenu>
                  <ActionMenu.Button className={styles.sdkButton}>
                    {gettingStarted[selectedLanguage]?.sdks[selectedSdk]?.name}
                  </ActionMenu.Button>
                  <ActionMenu.Overlay>
                    <ActionList>
                      {sdks.map(sdk => (
                        <ActionList.Item key={sdk} onSelect={() => setSelectedSdk(sdk)}>
                          {gettingStarted[selectedLanguage]?.sdks[sdk]?.name}
                        </ActionList.Item>
                      ))}
                    </ActionList>
                  </ActionMenu.Overlay>
                </ActionMenu>
              )}
            </>
          )}
        </div>
        {isLoading ? (
          <div className={styles.codeContainerSpinner}>
            <Spinner />
          </div>
        ) : (
          <>
            <div className={`${styles.codeContainer} ${showExpanded ? styles.expanded : ''}`}>
              <CopyToClipboardButton
                textToCopy={codeContent}
                ariaLabel="Copy to clipboard"
                className={styles.copyButton}
              />
              <CodeMirror
                fileName={`document.${getLanguageExt(selectedLanguage || '')}`}
                ariaLabelledBy={''}
                value={codeContent}
                height="100%"
                spacing={{
                  indentUnit: 2,
                  indentWithTabs: false,
                  lineWrapping: true,
                }}
                hideHelpUntilFocus
                onChange={() => {}}
                isReadOnly
              />
            </div>

            <Button
              className="border-top rounded-top-0 width-full fgColor-muted f6"
              onClick={() => setShowExpanded(!showExpanded)}
              leadingVisual={showExpanded ? FoldUpIcon : FoldDownIcon}
              variant="invisible"
            >
              {showExpanded ? 'Show less' : 'Show more'}
            </Button>
          </>
        )}
      </div>

      {showDialog && (
        <GettingStartedDialog
          gettingStarted={gettingStarted}
          modelName={selectedModel?.name || ''}
          openInCodespaceUrl="https://github.com"
          showCodespacesSuggestion={false}
          uiState={{
            preferredLanguage: selectedLanguage || '',
            preferredSdk: selectedSdk || '',
            sidebarTab: 0, // Dummy value to make TypeScript happy
            showSidebar: true, // Dummy value to make TypeScript happy
          }}
          setUiState={({preferredLanguage, preferredSdk}) => {
            setSelectedLanguage(preferredLanguage)
            setSelectedSdk(preferredSdk)
          }}
          onClose={() => setShowDialog(false)}
        />
      )}
    </>
  )
}

type language = 'csharp' | 'java' | 'js' | 'python' | 'rest'

function getLanguageExt(lang: language | string): string {
  const extensionMap: {[key in language]: string} = {
    csharp: 'cs',
    java: 'java',
    js: 'js',
    python: 'py',
    rest: 'sh',
  }

  return lang in extensionMap ? extensionMap[lang as keyof typeof extensionMap] : 'txt'
}

export function replaceParameters(template: string, model: RepoModel): string {
  if (!template) return ''
  const parameters = new Map<string, string>()
  parameters.set('system_message', 'You are a helpful assistant.')
  parameters.set('response_format', 'text')
  parameters.set('model_name', promptModelIdentifierFor(model))
  parameters.set('model_endpoint', 'https://models.github.ai/inference')
  parameters.set('temperature', '1.0')
  parameters.set('max_tokens', '1000')
  parameters.set('top_p', '1.0')

  const regex = /\{(\w+)\}/g
  return template.replace(regex, (match, key) => parameters.get(key) ?? match)
}
