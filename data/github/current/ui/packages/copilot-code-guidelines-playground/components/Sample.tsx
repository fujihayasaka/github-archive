import styles from '../CopilotCodeGuidelinesPlayground.module.css'
import {lazy, Suspense, useCallback, useState} from 'react'
import {testIdProps} from '@github-ui/test-id-props'
import Results from './Results'
import {Octicon} from '@primer/react/deprecated'
import {Blankslate} from '@primer/react/experimental'
import {Spinner, Button, FormControl, Link} from '@primer/react'
import {CopilotIcon, BeakerIcon, PlusIcon, PlusCircleIcon} from '@primer/octicons-react'
import {SampleCodeStatus, usePlaygroundContext} from '../PlaygroundContext'
import type {CodeComment, CodingGuideline} from '../PlaygroundContext'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'

const CodeMirror = lazy(() => import('@github-ui/code-mirror'))

export default function Sample() {
  const {
    promptCharLimit,
    sampleCode,
    sampleCodeStatus,
    setSampleCodeStatus,
    setSampleCode,
    codeComments,
    currentCodingGuideline,
    sampleCodeGenerationsPath,
    setCurrentCodingGuideline,
  } = usePlaygroundContext()
  const [isGeneratingSampleCode, setIsGeneratingSampleCode] = useState(false)
  const [codeGenerationErrorMessage, setCodeGenerationErrorMessage] = useState<string | null>(null)
  const [hasAddedSampleCode, setHasAddedSampleCode] = useState(false)

  const saveSampleCode = useCallback(
    (text: string) => {
      setSampleCodeStatus(SampleCodeStatus.WaitingToRun)
      setSampleCode(text)
    },
    [setSampleCode, setSampleCodeStatus],
  )

  const hasDescription = currentCodingGuideline.description !== null && currentCodingGuideline.description.length > 0
  const blankslateHeading = hasDescription ? 'Test your guideline on sample code' : 'Create your coding guideline'
  const blankslateDescription = hasDescription ? (
    'Iterate on your guideline to make sure Copilot catches the right things.'
  ) : (
    <>
      Be clear and specific about what Copilot should look for.{' '}
      <Link
        href="https://docs.github.com/early-access/copilot/code-review/configuring-coding-guidelines"
        target="_blank"
        rel="noreferrer"
        inline
      >
        Learn more in the docs.
      </Link>
    </>
  )

  if (hasAddedSampleCode) {
    return (
      <div className="d-flex flex-column gap-3 flex-1">
        <div className="d-flex flex-column border rounded-2 overflow-hidden flex-1">
          <div className="d-flex flex-md-items-center  flex-md-row flex-column gap-2 bgColor-muted border-bottom py-2 pl-3 pr-2">
            <h3 className="f4 d-flex gap-2">Sample</h3>
            <GenerateSampleButton
              generateCodeSample={generateCodeSample}
              isGeneratingSampleCode={isGeneratingSampleCode}
            />
            {codeGenerationErrorMessage && (
              <FormControl.Validation variant="error">{codeGenerationErrorMessage}</FormControl.Validation>
            )}
          </div>
          <div className="d-flex flex-column flex-md-row flex-1 overflow-hidden" {...testIdProps('sample-container')}>
            <div className={`flex-md-1 overflow-y-auto ${styles.sample}`}>
              <Suspense fallback={<></>}>
                <CodeMirror
                  height="100vh"
                  fileName={''}
                  value={sampleCode || ''}
                  ariaLabelledBy={'Sample'}
                  hideHelpUntilFocus={false}
                  spacing={{
                    indentUnit: 2,
                    indentWithTabs: false,
                    lineWrapping: true,
                  }}
                  isReadOnly={false}
                  onChange={saveSampleCode}
                  {...testIdProps('sample-content-editor')}
                />
              </Suspense>
            </div>
            <div className="flex-md-1 border-top border-md-top-0 border-md-left p-3">
              <CodeReviewResults sampleCodeStatus={sampleCodeStatus} codeComments={codeComments} />
            </div>
          </div>
        </div>
      </div>
    )
  } else {
    return (
      <div
        className="flex-1 border rounded-2 d-flex flex-column flex-justify-center"
        {...testIdProps('blankslate-container')}
      >
        <Blankslate spacious>
          <Blankslate.Visual>
            <Octicon icon={BeakerIcon} size={24} color="fg.muted" />
          </Blankslate.Visual>
          <Blankslate.Heading>{blankslateHeading}</Blankslate.Heading>
          <Blankslate.Description>{blankslateDescription}</Blankslate.Description>
          <div className="gap-2 d-flex mt-3">
            <GettingStartedActions
              hasDescription={hasDescription}
              setHasAddedSampleCode={setHasAddedSampleCode}
              generateCodeSample={generateCodeSample}
              setCurrentCodingGuideline={setCurrentCodingGuideline}
              isGeneratingSampleCode={isGeneratingSampleCode}
            />
          </div>
        </Blankslate>
      </div>
    )
  }

  async function generateCodeSample() {
    if (currentCodingGuideline.description === null || currentCodingGuideline.description === '') {
      setCodeGenerationErrorMessage('Needs a code guideline description to generate code sample')
    } else if (currentCodingGuideline.description.length > promptCharLimit) {
      setCodeGenerationErrorMessage('Description is too long to generate code sample')
    } else {
      setIsGeneratingSampleCode(true)
      const resp = await verifiedFetchJSON(sampleCodeGenerationsPath, {
        method: 'POST',
        body: {description: currentCodingGuideline.description},
      })

      setIsGeneratingSampleCode(false)
      if (resp.ok) {
        const json = await resp.json()
        setCodeGenerationErrorMessage(null)
        setSampleCode(json.sampleCode)
        setHasAddedSampleCode(true)
      } else {
        setCodeGenerationErrorMessage((await resp.json()).error)
      }
    }
  }
}

function CodeReviewResults({
  sampleCodeStatus,
  codeComments,
}: {
  sampleCodeStatus: SampleCodeStatus
  codeComments: CodeComment[]
}) {
  if (sampleCodeStatus === SampleCodeStatus.Loading) {
    return (
      <div className="height-full d-flex flex-column flex-justify-center flex-items-center gap-2 fgColor-muted">
        <div className="d-flex position-relative fgColor-accent">
          <Spinner size="medium" srText={null} />
          <span className="d-flex position-absolute inset-0 p-2">
            <CopilotIcon size={16} />
          </span>
        </div>
        Generating response…
      </div>
    )
  } else if (sampleCodeStatus === SampleCodeStatus.WaitingToRun) {
    return (
      <div
        className={`height-full d-flex flex-column flex-justify-center flex-items-center gap-2 fgColor-muted ${styles.runWhenReady}`}
        {...testIdProps('run-when-ready')}
      >
        Click &quot;Run&quot; to test this guideline...
      </div>
    )
  } else {
    return <Results results={codeComments} />
  }
}

function GettingStartedActions({
  hasDescription,
  setHasAddedSampleCode,
  setCurrentCodingGuideline,
  generateCodeSample,
  isGeneratingSampleCode,
}: {
  hasDescription: boolean
  setHasAddedSampleCode: (value: boolean) => void
  setCurrentCodingGuideline: React.Dispatch<React.SetStateAction<CodingGuideline>>
  generateCodeSample: () => Promise<void>
  isGeneratingSampleCode: boolean
}) {
  const sampleGuidelines = [
    {
      name: 'Avoid using magic numbers',
      description:
        "Don't use magic numbers in code. Numbers should be defined as constants or variables with meaningful names.",
    },
    {
      name: 'Always tag metrics with the current environment',
      description:
        'Always include a `env` tag with the current environment when emitting metrics, for example, `env:prod` or `env:dev`.',
    },
    {
      name: "Don't use 'SELECT *' in SQL queries",
      description:
        "Don't use `SELECT *` in SQL queries. Always specify the columns you want to select. `COUNT(*)` is allowed.",
    },
    {
      name: "Use 'fetch' for HTTP requests",
      description: 'Use `fetch` for HTTP requests, not `axios` or `superagent` or other libraries.',
    },
  ]

  if (hasDescription) {
    // If the user has entered a description, we guide them toward adding sample code
    return (
      <>
        <Button
          onClick={() => setHasAddedSampleCode(true)}
          leadingVisual={PlusIcon}
          className="flex-self-start"
          {...testIdProps('add-sample-code-button')}
        >
          Add sample code
        </Button>
        <GenerateSampleButton generateCodeSample={generateCodeSample} isGeneratingSampleCode={isGeneratingSampleCode} />
      </>
    )
  } else {
    // If there is no description, we guide them toward adding one
    return (
      <div className="col-12 col-xl-10 mx-auto gap-2 text-center">
        {sampleGuidelines.map(sampleGuideline => {
          return (
            <Button
              variant="invisible"
              key={sampleGuideline.name}
              onClick={() =>
                setCurrentCodingGuideline(prev => ({
                  ...prev,
                  name: sampleGuideline.name,
                  description: sampleGuideline.description,
                }))
              }
              leadingVisual={PlusCircleIcon}
              className="color-shadow-small mb-3 mx-1 py-1 border rounded d-inline-flex flex-1 circle"
              labelWrap
              {...testIdProps('accept-sample-guideline-button')}
            >
              {sampleGuideline.name}
            </Button>
          )
        })}
      </div>
    )
  }
}

function GenerateSampleButton({
  generateCodeSample,
  isGeneratingSampleCode,
}: {
  generateCodeSample: () => Promise<void>
  isGeneratingSampleCode: boolean
}) {
  return (
    <Button
      onClick={generateCodeSample}
      disabled={isGeneratingSampleCode}
      loading={isGeneratingSampleCode}
      leadingVisual={CopilotIcon}
      loadingAnnouncement={'Generating code sample'}
      {...testIdProps('generate-sample-code-button')}
    >
      Generate from description
    </Button>
  )
}
