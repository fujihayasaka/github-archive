import {sendEvent} from '@github-ui/hydro-analytics'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

import {getAllRegisteredCommands} from '../commands-registry'
import {GlobalCommands} from '../components/GlobalCommands'
import {ScopedCommands} from '../components/ScopedCommands'
import {
  chordCommand,
  conflictingChordCommand,
  expectEventObject,
  flaggedCommand,
  mockHandler,
  sequenceCommand,
} from './__fixtures__/commands'
import {withDisabledCharacterKeys} from './utils'

jest.mock('@github-ui/hydro-analytics', () => {
  return {
    ...jest.requireActual('@github-ui/hydro-analytics'),
    sendEvent: jest.fn(),
  }
})

const isFeatureEnabledMock = jest.fn().mockReturnValue(true)
jest.mock('@github-ui/feature-flags', () => ({
  isFeatureEnabled(...args: unknown[]) {
    return isFeatureEnabledMock(...args)
  },
}))

const querySelector = jest.fn()
querySelector.mockImplementation((selector: string) => {
  if (selector !== '[role="dialog"][aria-modal="true"]') return []
  return screen.queryAllByRole('dialog')
})
jest.spyOn(document, 'querySelectorAll').mockImplementation(querySelector)

// Since jsdom doesn't actually render the elements, the calculated height is always 0
// We need to mock the height to simulate the portal being open
const addHeightToPortals = () => {
  const portalContent = screen.getAllByTestId('portal-content')
  for (const portal of portalContent) {
    jest.spyOn(portal, 'clientHeight', 'get').mockReturnValue(1)
  }
}

describe('GlobalCommands', () => {
  beforeEach(() => {
    ;(sendEvent as jest.Mock).mockReset()
    querySelector.mockClear()
  })

  it('fires commands when triggered', async () => {
    const handler = mockHandler()
    render(<GlobalCommands commands={{[chordCommand.id]: handler}} />)

    await chordCommand.fire()

    expect(handler).toHaveBeenCalledWith(expectEventObject(chordCommand))
  })

  it('does not fire commands if modal is open', async () => {
    const handler = mockHandler()
    render(
      <>
        <GlobalCommands commands={{[chordCommand.id]: handler}} />
        <div role="dialog" aria-modal="true">
          <p data-testid="portal-content">Portal content</p>
        </div>
      </>,
    )
    addHeightToPortals()

    await chordCommand.fire()

    expect(handler).not.toHaveBeenCalled()
  })

  it('fires commands if rendered inside modal', async () => {
    const handler = mockHandler()
    render(
      <div role="dialog" aria-modal="true">
        <GlobalCommands commands={{[chordCommand.id]: handler}} />
        <p data-testid="portal-content">Portal content</p>
      </div>,
    )
    addHeightToPortals()

    await chordCommand.fire()

    expect(handler).toHaveBeenCalledWith(expectEventObject(chordCommand))
  })

  it('fires if rendered inside modal dialog', async () => {
    const handler = mockHandler()
    render(
      <dialog data-testid="dialog">
        <GlobalCommands commands={{[chordCommand.id]: handler}} />
        <p data-testid="portal-content">Portal content</p>
      </dialog>,
    )
    addHeightToPortals()

    const dialog: HTMLDialogElement = screen.getByTestId('dialog')
    dialog.showModal()

    await chordCommand.fire()

    expect(handler).toHaveBeenCalledWith(expectEventObject(chordCommand))
  })

  it('does not trigger if in a modal that is not on top', async () => {
    const handler = mockHandler()
    render(
      <>
        <div role="dialog" aria-modal="true">
          <GlobalCommands commands={{[chordCommand.id]: handler}} />
          <p data-testid="portal-content">Portal content</p>
        </div>
        <div role="dialog" aria-modal="true">
          <p data-testid="portal-content">Portal content</p>
        </div>
      </>,
    )
    addHeightToPortals()

    await chordCommand.fire()

    expect(handler).not.toHaveBeenCalled()
  })

  it('triggers if in the top most portal', async () => {
    const handler = mockHandler()
    render(
      <>
        <div id="__primerPortalRoot__">
          <p data-testid="portal-content">Portal content</p>
        </div>
        <div id="table-portal-root">
          <GlobalCommands commands={{[chordCommand.id]: handler}} />
          <p data-testid="portal-content">Portal content</p>
        </div>
      </>,
    )
    addHeightToPortals()

    await chordCommand.fire()

    expect(handler).toHaveBeenCalledWith(expectEventObject(chordCommand))
  })

  it('works with sequences', async () => {
    const handler = mockHandler()
    render(<GlobalCommands commands={{[sequenceCommand.id]: handler}} />)

    await sequenceCommand.fire()

    expect(handler).toHaveBeenCalledWith(expectEventObject(sequenceCommand))
  })

  it('does not fire single character key commands when disabled', async () =>
    await withDisabledCharacterKeys(async () => {
      const handler = mockHandler()
      render(<GlobalCommands commands={{[sequenceCommand.id]: handler}} />)

      await sequenceCommand.fire()

      expect(querySelector).not.toHaveBeenCalled()

      expect(handler).not.toHaveBeenCalled()
    }))

  it('does not query the DOM if a matching command is not found', async () => {
    const handler = mockHandler()
    render(<GlobalCommands commands={{[chordCommand.id]: handler}} />)

    await sequenceCommand.fire()

    expect(querySelector).not.toHaveBeenCalled()
  })

  it('does not fire sequences when there is a long delay between presses', async () => {
    jest.useFakeTimers()

    const handler = mockHandler()
    const {user} = render(<GlobalCommands commands={{[sequenceCommand.id]: handler}} />)

    await user.keyboard('g')
    jest.advanceTimersByTime(10_000)
    await user.keyboard('q')

    expect(handler).not.toHaveBeenCalled()
  })

  it("fires non-sequence commands at the end of a sequence that doesn't match a command", async () => {
    const handler = mockHandler()
    const {user} = render(<GlobalCommands commands={{[chordCommand.id]: handler}} />)

    await user.keyboard('g')
    await chordCommand.fire()

    expect(handler).toHaveBeenCalledWith(expectEventObject(chordCommand))
  })

  it('does not fire single character key commands when focus is in a form field', async () => {
    const handler = mockHandler()
    render(
      <>
        <GlobalCommands commands={{[sequenceCommand.id]: handler}} />
        <textarea />
      </>,
    )

    screen.getByRole('textbox').focus()
    await sequenceCommand.fire()

    expect(querySelector).not.toHaveBeenCalled()

    expect(handler).not.toHaveBeenCalled()
  })

  it('fires chord commands when focus is in a form field', async () => {
    const handler = mockHandler()
    render(
      <>
        <GlobalCommands commands={{[chordCommand.id]: handler}} />
        <textarea />
      </>,
    )

    screen.getByRole('textbox').focus()
    await chordCommand.fire()

    expect(handler).toHaveBeenCalled()
  })

  it('does not fire a handled scoped command', async () => {
    const globalHandler = mockHandler()
    const innerHandler = mockHandler()
    render(
      <>
        <GlobalCommands commands={{[chordCommand.id]: globalHandler}} />
        <ScopedCommands commands={{[chordCommand.id]: innerHandler}}>
          <textarea />
        </ScopedCommands>
      </>,
    )

    screen.getByRole('textbox').focus()
    await chordCommand.fire()

    expect(innerHandler).toHaveBeenCalledWith(expectEventObject(chordCommand))
    expect(globalHandler).not.toHaveBeenCalled()
  })

  it('does not fire twice if rendered twice (stops propagation)', async () => {
    jest.useFakeTimers()

    const handler = mockHandler()
    render(
      <>
        <GlobalCommands commands={{[chordCommand.id]: handler}} />
        <GlobalCommands commands={{[chordCommand.id]: handler}} />
      </>,
    )

    await chordCommand.fire()

    expect(handler).toHaveBeenCalledWith(expectEventObject(chordCommand))
    expect(handler).toHaveBeenCalledTimes(1)
  })

  it('detaches the listener on dismount', async () => {
    const handler = mockHandler()
    const {unmount} = render(<GlobalCommands commands={{[chordCommand.id]: handler}} />)

    unmount()
    await chordCommand.fire()

    expect(handler).not.toHaveBeenCalled()
  })

  it('warns if commands are registered with conflicting keybindings', () => {
    const warn = jest.spyOn(console, 'warn').mockImplementation(() => {})

    render(
      <>
        <GlobalCommands commands={{[chordCommand.id]: jest.fn()}} />
        <GlobalCommands commands={{[conflictingChordCommand.id]: jest.fn()}} />
      </>,
    )

    expect(warn).toHaveBeenNthCalledWith(
      1,
      'The keybinding (Control+Shift+Enter) for the "ui-commands:conflicting-chord" command conflicts with the keybinding for the already-registered command(s) "ui-commands:test-chord". This may result in unpredictable behavior.',
    )

    // the result of triggering a conflicting command is intentionally left undefined and untested
  })

  it('does not warn if the same command is rendered twice', () => {
    const warn = jest.spyOn(console, 'warn').mockImplementation(() => {})

    render(
      <>
        <GlobalCommands commands={{[chordCommand.id]: jest.fn()}} />
        <GlobalCommands commands={{[chordCommand.id]: jest.fn()}} />
      </>,
    )

    expect(warn).not.toHaveBeenCalled()
  })

  it('records metrics for executed commands', async () => {
    render(<GlobalCommands commands={{[chordCommand.id]: jest.fn()}} />)
    await chordCommand.fire()

    expect(sendEvent).toHaveBeenCalledWith('command.trigger', {
      app_name: 'ui-commands',
      command_id: chordCommand.id,
      trigger_type: 'keybinding',
      target_element_html: expect.stringMatching(/^<body.*>$/),
      keybinding: 'Control+Shift+Enter',
    })
  })

  it('binds flagged command when feature is enabled', async () => {
    isFeatureEnabledMock.mockReturnValue((flags: string) => flags === 'TEST_FEATURE')

    const handler = mockHandler()
    render(<GlobalCommands commands={{[flaggedCommand.id]: handler}} />)

    await flaggedCommand.fire()

    expect(handler).toHaveBeenCalledWith(expectEventObject(flaggedCommand))
  })

  it('does not bind flagged command when feature is disabled', async () => {
    isFeatureEnabledMock.mockReturnValue(false)

    const handler = mockHandler()
    render(<GlobalCommands commands={{[flaggedCommand.id]: handler}} />)

    await flaggedCommand.fire()

    expect(handler).not.toHaveBeenCalled()
  })

  it('records commands in the global registry', () => {
    const {unmount} = render(<GlobalCommands commands={{[chordCommand.id]: jest.fn()}} />)

    expect(getAllRegisteredCommands()[0]?.commands.filter(c => c.id === chordCommand.id)).toBeTruthy()

    unmount()

    expect(getAllRegisteredCommands()[0]?.commands.filter(c => c.id === chordCommand.id)).toBeFalsy()
  })
})
