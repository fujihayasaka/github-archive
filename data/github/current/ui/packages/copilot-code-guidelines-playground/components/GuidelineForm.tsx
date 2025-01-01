import {useState} from 'react'
import {Button, FormControl, Link, TextInput, Textarea, IconButton} from '@primer/react'
import {UndoIcon, TrashIcon} from '@primer/octicons-react'
import {usePlaygroundContext, type CodingGuidelinePath} from '../PlaygroundContext'
import {Banner, Blankslate, Dialog} from '@primer/react/experimental'
import {testIdProps} from '@github-ui/test-id-props'

type CharacterCountProps = {
  text: string
  promptCharLimit: number
}

export default function GuidelineForm() {
  const {
    initialCodingGuideline,
    currentCodingGuideline,
    setCurrentCodingGuideline,
    errorMessage,
    saveCodeGuideline,
    promptCharLimit,
    codingGuidelinePaths,
    setCodingGuidelinePaths,
  } = usePlaygroundContext()
  const [isDirty, setIsDirty] = useState(false)
  const [isFilePathModalOpen, setIsFilePathModalOpen] = useState(false)
  const [filePathText, setFilePathText] = useState('')
  const [filePathValidationMessage, setFilePathValidationMessage] = useState<null | string>(null)

  return (
    <form
      className="d-flex flex-column border rounded-2 overflow-y-auto col-xl-3 col-lg-4"
      onSubmit={saveCodeGuideline}
    >
      <div className="d-flex flex-items-center flex-justify-between gap-2 bgColor-muted border-bottom py-2 pl-3 pr-2">
        <h2 className="f4">Definition</h2>
        <IconButton
          icon={UndoIcon}
          onClick={resetForm}
          aria-label="Undo all changes"
          size="small"
          variant="invisible"
          // If we removed the button and then add it it causes the header height to change and the whole form will jump.
          // Instead, use opacity so that there isn't a visual jump when the button is toggled.
          sx={{opacity: isDirty ? 1 : 0}}
          // Still needs to be disabled so that the button is not clickable or focusable.
          disabled={!isDirty}
          {...testIdProps('undo-changes-button')}
        />
      </div>
      <div className="d-flex flex-column flex-1 gap-3 p-3">
        <p className="mb-0 color-fg-muted">
          Be clear and specific about what Copilot should look for.{' '}
          <Link
            href="https://docs.github.com/early-access/copilot/code-review/configuring-coding-guidelines"
            target="_blank"
            rel="noreferrer"
            inline
          >
            Learn more in the docs.
          </Link>
        </p>
        {errorMessage && (
          <Banner title={errorMessage} variant="critical" className="mb-2" {...testIdProps('error-banner')} />
        )}
        <FormControl required>
          <FormControl.Label required>Name</FormControl.Label>
          <TextInput
            block
            value={currentCodingGuideline.name || ''}
            onChange={handleNameChange}
            {...testIdProps('name-input')}
          />
        </FormControl>

        <FormControl required>
          <FormControl.Label required>Description</FormControl.Label>
          <CharacterCount text={currentCodingGuideline.description || ''} promptCharLimit={promptCharLimit} />
          <Textarea
            block
            rows={12}
            resize="vertical"
            value={currentCodingGuideline.description || ''}
            onChange={handleDescriptionChange}
            {...testIdProps('description-input')}
          />
        </FormControl>
        <div className="d-flex flex-column border rounded-2 overflow-hidden">
          <div className="d-flex flex-items-center flex-justify-between gap-2 bgColor-muted border-bottom py-2 pl-3 pr-2">
            <h3 className="f5">File paths (optional)</h3>
            <Button onClick={() => setIsFilePathModalOpen(true)} {...testIdProps('open-file-path-modal')}>
              Add file path
            </Button>
          </div>
          <div>
            {codingGuidelinePaths.filter(path => !path.markedForDestroy).length === 0 && (
              <Blankslate className="text-center">
                <Blankslate.Description>
                  Run this guideline on specific files or directories. By default{' '}
                  <Link
                    inline
                    target="_blank"
                    href="https://docs.github.com/early-access/copilot/code-reviews/using-copilot-code-reviews#about-copilot-code-reviews"
                    rel="noreferrer"
                  >
                    all supported file types
                  </Link>{' '}
                  are reviewed.
                </Blankslate.Description>
              </Blankslate>
            )}
            {codingGuidelinePaths.map(path => (
              <PathRow path={path} key={path.path} removePath={removePath} />
            ))}
            {isFilePathModalOpen && (
              <Dialog
                title="Include by pattern"
                subtitle="Paths that match the matching pattern will be targeted by this guideline"
                width="medium"
                onClose={cancelAddingFilePath}
                footerButtons={[
                  {
                    buttonType: 'default',
                    content: 'Cancel',
                    onClick: cancelAddingFilePath,
                  },
                  {
                    buttonType: 'primary',
                    content: 'Add inclusion pattern',
                    onClick: addFilePath,
                    ...testIdProps('add-file-path-button'),
                  },
                ]}
              >
                <FormControl required>
                  <FormControl.Label required>Path inclusion pattern</FormControl.Label>
                  <TextInput
                    block
                    value={filePathText}
                    onChange={e => {
                      setFilePathText(e.target.value)
                    }}
                    {...testIdProps('file-path-input')}
                  />

                  {filePathValidationMessage && (
                    <FormControl.Validation variant="error">{filePathValidationMessage}</FormControl.Validation>
                  )}

                  <FormControl.Caption>
                    Example patterns: &quot;main&quot;, &quot;releases/**/*&quot;, &quot;tests/**/*_test.ts&quot;
                  </FormControl.Caption>
                </FormControl>
              </Dialog>
            )}
          </div>
        </div>
      </div>
    </form>
  )

  function handleDescriptionChange(event: React.ChangeEvent<HTMLTextAreaElement>) {
    setIsDirty(true)
    setCurrentCodingGuideline({...currentCodingGuideline, ...{description: event.target.value}})
  }

  function handleNameChange(event: React.ChangeEvent<HTMLInputElement>) {
    setIsDirty(true)
    setCurrentCodingGuideline({...currentCodingGuideline, ...{name: event.target.value}})
  }

  function resetForm() {
    setCurrentCodingGuideline(initialCodingGuideline)
    setIsDirty(false)
  }

  function cancelAddingFilePath() {
    setIsFilePathModalOpen(false)
    setFilePathText('')
  }

  function addFilePath() {
    if (filePathText === '') {
      setFilePathValidationMessage('Path cannot be blank')
      return
    } else if (codingGuidelinePaths.some(path => path.path === filePathText)) {
      setFilePathValidationMessage('Path already exists')
      return
    } else if (filePathText.includes(' ')) {
      setFilePathValidationMessage('Path cannot contain spaces')
      return
    } else {
      setFilePathValidationMessage(null)
      setCodingGuidelinePaths([...codingGuidelinePaths, {path: filePathText, id: null, markedForDestroy: false}])
      setIsFilePathModalOpen(false)
      setFilePathText('')
    }
  }

  function removePath(path: string | null) {
    setCodingGuidelinePaths(
      codingGuidelinePaths.map(codingGuidelinePath => {
        if (codingGuidelinePath.path === path) {
          return {...codingGuidelinePath, markedForDestroy: true}
        }
        return codingGuidelinePath
      }),
    )
  }
}
function CharacterCount({text, promptCharLimit}: CharacterCountProps) {
  const currentCount = (
    <>
      <span className="text-tabular-nums">{text.length}</span> / {promptCharLimit} characters
    </>
  )
  return (
    <>
      {text.length > promptCharLimit ? (
        <FormControl.Validation variant="error">{currentCount}</FormControl.Validation>
      ) : (
        // This is a direct child, it just doesn't know that because it is a fragment within a function call
        // eslint-disable-next-line primer-react/direct-slot-children
        <FormControl.Caption>{currentCount}</FormControl.Caption>
      )}
    </>
  )
}

type PathRowProps = {
  path: CodingGuidelinePath
  removePath: (path: string | null) => void
}

function PathRow({path, removePath}: PathRowProps) {
  if (path.markedForDestroy) return null

  return (
    <div className="Box-row py-2 flex-items-center d-flex" {...testIdProps('path-row')}>
      <div className="flex-1">
        <span className="bgColor-accent-muted fgColor-accent rounded f6 py-1 px-2 text-mono wb-break-word">
          {path.path}
        </span>
      </div>
      <IconButton
        icon={TrashIcon}
        variant="invisible"
        size="small"
        aria-label="Remove this file path"
        onClick={() => removePath(path.path)}
        {...testIdProps('remove-file-path-button')}
      />
    </div>
  )
}
