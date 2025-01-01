import {CopyToClipboardButton} from '@github-ui/copy-to-clipboard/Button'
import React, {lazy} from 'react'
import type {ModelState, PlaygroundRequestParameters} from '../../../types'
import {getIndex, pythonRagCodeSnippet} from '../../../utils/rag-index-manager'
import {defaultResponseFormat} from '../../../utils/model-state'
import type {ModelPersistentUIState} from '../../../utils/playground-local-storage'
import styles from './PlaygroundSharedStyles.module.css'

const CodeMirror = lazy(() => import('@github-ui/code-mirror'))

function replaceKeywords(template: string, values: PlaygroundRequestParameters) {
  const regex = /\{(\w+)\}/g
  return template.replace(regex, (match, key) => values[key] ?? match)
}

export type language = 'csharp' | 'java' | 'js' | 'python' | 'rest'

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

export function PlaygroundCodeSnippet({model, uiState}: {model: ModelState; uiState: ModelPersistentUIState}) {
  // TODO: Change this to the gateway URL when we are ready to start deprecating Nexus and documentation
  // is being updated
  // ref: https://github.com/github/github/blob/f56a3cef84aecd42aceb731ac996eac6c48845c5/ui/packages/github-models/utils/rag-index-manager.ts#L5-L7
  // ref: playground_url, azure_ai_playground_url, and github_models_gateway FF
  const playgroundUrl = 'https://models.inference.ai.azure.com'

  const {systemPrompt, parameters, catalogData, gettingStarted, responseFormat} = model

  // Note: Never directly modify state
  const enrichedParameters = Object.assign({}, parameters)

  enrichedParameters['system_message'] = systemPrompt || ''
  enrichedParameters['response_format'] = responseFormat || defaultResponseFormat
  enrichedParameters['model_name'] = catalogData.original_name

  enrichedParameters['model_endpoint'] = playgroundUrl

  const {preferredSdk: selectedSDK, preferredLanguage: selectedLanguage} = uiState
  const snippet = gettingStarted[selectedLanguage]

  const extension = getLanguageExt(selectedLanguage)

  let content = 'Code snippet not available'

  if (snippet) {
    const sdkEntry = snippet.sdks[selectedSDK]
    if (sdkEntry && sdkEntry.codeSamples.length > 0) {
      content = sdkEntry.codeSamples
    }

    // Replace the code snippet content with the hard-coded RAG code snippet, only for Python + Azure AI Inference SDK
    if (model.isUseIndexSelected && selectedLanguage === 'python' && selectedSDK.startsWith('azure-ai')) {
      content = pythonRagCodeSnippet
      const index = getIndex()
      enrichedParameters['search_endpoint'] = index.endpoint
      enrichedParameters['search_index'] = index.name
    }

    content = replaceKeywords(content, enrichedParameters)
  }

  return (
    <div className="d-flex position-relative flex-column overflow-auto" style={{flex: 1}}>
      <CopyToClipboardButton className={styles.copyButton} textToCopy={content} ariaLabel={'Copy to clipboard'} />

      <div className="position-absolute width-full" style={{left: 0, top: 0}}>
        <React.Suspense fallback={<></>}>
          <CodeMirror
            fileName={`document.${extension}`}
            value={content}
            ariaLabelledBy={''}
            height="100%"
            spacing={{
              indentUnit: 2,
              indentWithTabs: false,
              lineWrapping: false,
            }}
            hideHelpUntilFocus
            onChange={() => {}}
            isReadOnly
          />
        </React.Suspense>
      </div>
    </div>
  )
}
