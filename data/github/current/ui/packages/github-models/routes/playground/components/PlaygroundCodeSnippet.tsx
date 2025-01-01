import {CopyToClipboardButton} from '@github-ui/copy-to-clipboard/Button'
import {usePlaygroundState} from '../../../contexts/PlaygroundStateContext'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import React, {lazy} from 'react'
import type {ModelState, ShowModelPayload, PlaygroundRequestParameters} from '../../../types'
import {getIndex, pythonRagCodeSnippet} from '../../../utils/rag-index-manager'
import {defaultResponseFormat} from '../../../utils/model-state'

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

export function PlaygroundCodeSnippet({model}: {model: ModelState}) {
  const {playgroundUrl} = useRoutePayload<ShowModelPayload>()

  const {systemPrompt, parameters, catalogData, gettingStarted, responseFormat} = model

  // Note: Never directly modify state
  const enrichedParameters = Object.assign({}, parameters)

  enrichedParameters['system_message'] = systemPrompt || ''
  enrichedParameters['response_format'] = responseFormat || defaultResponseFormat
  enrichedParameters['model_name'] = catalogData.original_name

  // The model_endpoint templatized variable is expected to be the root URL.
  // "/chat/completions" gets appended depending on the language+SDK code snippet
  enrichedParameters['model_endpoint'] = playgroundUrl.replace('/chat/completions', '')

  const {selectedSDK, selectedLanguage} = usePlaygroundState()
  const snippet = gettingStarted[selectedLanguage]

  const extension = getLanguageExt(selectedLanguage)

  if (!snippet) {
    return null
  }

  const hasCodeSample = snippet.sdks[selectedSDK]

  let content = 'Code snippet not available'
  if (hasCodeSample) {
    if (hasCodeSample.codeSamples.length > 0) {
      content = hasCodeSample.codeSamples
    }
  } else {
    const defaultSDK = Object.values(snippet.sdks)[0]
    if (defaultSDK) {
      content = defaultSDK.codeSamples
    }
  }

  // Replace the code snippet content with the hard-coded RAG code snippet, only for Python + Azure AI Inference SDK
  if (model.isUseIndexSelected && selectedLanguage === 'python' && selectedSDK.startsWith('azure-ai')) {
    content = pythonRagCodeSnippet
    const index = getIndex()
    enrichedParameters['search_endpoint'] = index.endpoint
    enrichedParameters['search_index'] = index.name
  }

  content = replaceKeywords(content, enrichedParameters)

  return (
    <div className="d-flex position-relative flex-column overflow-auto" style={{flex: 1}}>
      <CopyToClipboardButton
        className="position-absolute"
        sx={{right: '8px', top: '8px', zIndex: 10}}
        textToCopy={content}
        ariaLabel={'Copy to clipboard'}
      />

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
