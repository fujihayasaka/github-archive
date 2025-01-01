import {type ChangeEvent, useCallback, useRef} from 'react'
import type {EvalsRow, ModelState} from '../../../types'
import {buildEvalsConfig} from '../evals-config'
import type {Config, DataRow, EvaluatorCfg} from '../evals-sdk/config'
import type {PromptEvalsManager} from '../prompt-evals-manager'

const defaultFileName = 'github-models.yaml'

/**
 * @param onImport Optional callback when import is starting, after selecting a file
 * @returns {exportSession, importSession, fileInputRef}
 */
export function useExportImportSession(
  manager: PromptEvalsManager,
  model: ModelState,
  systemPrompt: string | undefined,
  prompt: string,
  rows: DataRow[],
  evaluators: EvaluatorCfg[],
  onImport?: () => void,
) {
  const exportSession = useCallback(async () => {
    // eslint-disable-next-line import/no-extraneous-dependencies
    const jsYaml = await import('js-yaml')
    const cfg: Config = buildEvalsConfig(model, systemPrompt, prompt, rows, evaluators)
    const content = jsYaml.dump(cfg)

    const blob = new Blob([content], {
      type: 'text/yaml',
    })

    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.style.display = 'none'
    a.href = url
    a.download = defaultFileName
    document.body.appendChild(a)
    a.click()
    document.body.removeChild(a)
    window.URL.revokeObjectURL(url)
  }, [evaluators, model, prompt, rows, systemPrompt])

  const importSession = useCallback(
    async (e: ChangeEvent<HTMLInputElement>) => {
      onImport?.()

      const file = e.target?.files && e.target.files[0]
      if (!file) {
        return
      }

      // Read file
      const content = await new Promise<string>((resolve, reject) => {
        const reader = new FileReader()
        reader.onload = () => {
          resolve(reader.result as string)
        }
        reader.onerror = reject
        reader.readAsText(file)
      })

      // eslint-disable-next-line import/no-extraneous-dependencies
      const jsYaml = await import('js-yaml')

      try {
        const cfg = jsYaml.load(content) as Config

        if (cfg.prompts && cfg.prompts.length > 0) {
          // For now we only import the first prompt. Once we support additional message pairs
          // we'll revisit this.
          const firstPrompt = cfg.prompts[0]!
          if (!('messages' in firstPrompt) || !firstPrompt.messages?.length) {
            throw new Error('Only prompts with message pairs are supported')
          }

          const userMessage = firstPrompt.messages.find(m => m.role === 'user')
          if (!userMessage) {
            throw new Error('Prompt must have a user message')
          }

          manager.setPromptInput(userMessage.message)

          const systemMessage = firstPrompt.messages.find(m => m.role === 'system')
          if (systemMessage) {
            manager.setSystemPrompt(systemMessage.message)
          }
        }

        if (cfg.datasets && cfg.datasets.length > 0) {
          const dataset = cfg.datasets[0]!
          if ('rows' in dataset) {
            for (const row of dataset.rows) {
              manager.evalsAddRow(row as EvalsRow)
            }
          }
        }

        if (cfg?.evaluators?.length > 0) {
          for (const evaluator of cfg.evaluators) {
            manager.evalsAddEvaluator({
              config: evaluator,
              readonly: false,
            })
          }
        }
      } catch {
        manager.setError('Error during import')
      }

      // Reset file input
      e.target.value = ''
    },
    [manager, onImport],
  )

  const fileInputRef = useRef<HTMLInputElement>(null)

  return {
    exportSession,
    importSession,
    fileInputRef,
  }
}
