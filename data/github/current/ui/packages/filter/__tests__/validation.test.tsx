import {expectAnalyticsEvents} from '@github-ui/analytics-test-utils'
import {render} from '@github-ui/react-core/test-utils'
import {screen, waitFor} from '@testing-library/react'

import {Filter} from '../Filter'
import {
  AssigneeFilterProvider,
  CreatedFilterProvider,
  ParentIssueFilterProvider,
  ProjectFilterProvider,
  StateFilterProvider,
} from '../providers'
import {updateFilterValue} from '../test-utils'
import {type FilterProvider, ProviderSupportStatus} from '../types'
import {
  expectEmptyValueMessage,
  expectErrorMessage,
  expectNoErrorMessage,
  setupAsyncErrorHandler,
  setupIssuesMockApi,
  setupProjectsMockApi,
  setupUsersMockApi,
} from './utils/helpers'
import {blurInput} from './utils/interaction-test-helpers'

describe('Validation', () => {
  let onValidation: jest.Mock
  setupAsyncErrorHandler()

  function renderFilter(filterProviders: FilterProvider[]) {
    onValidation = jest.fn()
    render(
      <Filter
        id="test-filter-bar"
        label="Filter"
        context={{repo: 'github/github'}}
        providers={filterProviders}
        onValidation={onValidation}
      />,
    )

    expect(screen.getByTestId('filter-input')).toHaveAttribute('aria-describedby', '')
  }

  async function appendToFilter(key: string, value: string = '') {
    await updateFilterValue(`${key}${value ? `:${value} ` : ''}`)

    await waitFor(() => {
      expect(onValidation).toHaveBeenCalled()
    })
  }

  describe('Freeform', () => {
    it('does not show validation messages when showValidationMessage is false', async () => {
      renderFilter([
        new StateFilterProvider('mixed', {
          support: {status: ProviderSupportStatus.Supported},
          filterTypes: {
            inclusive: true,
            exclusive: true,
            valueless: false,
            multiKey: false,
            multiValue: true,
          },
        }),
      ])

      await appendToFilter('test')

      await waitFor(() => {
        expect(onValidation).toHaveBeenCalled()
      })

      expectNoErrorMessage()
    })
  })

  describe('State', () => {
    it('shows error message when state is invalid', async () => {
      renderFilter([
        new StateFilterProvider('mixed', {
          support: {status: ProviderSupportStatus.Supported},
          filterTypes: {
            inclusive: true,
            exclusive: true,
            valueless: false,
            multiKey: false,
            multiValue: true,
          },
        }),
      ])

      await appendToFilter('state', 'fake')

      await expectErrorMessage('state', 'fake')
    })

    it('does not show error message when state value is valid', async () => {
      renderFilter([
        new StateFilterProvider('mixed', {
          support: {status: ProviderSupportStatus.Supported},
          filterTypes: {
            inclusive: true,
            exclusive: true,
            valueless: false,
            multiKey: false,
            multiValue: true,
          },
        }),
      ])

      await appendToFilter('state', 'open')

      expectNoErrorMessage()
    })
  })

  describe('ParentIssue', () => {
    setupIssuesMockApi()

    it('shows error message when issue is invalid', async () => {
      renderFilter([new ParentIssueFilterProvider()])

      await appendToFilter('parent-issue', 'fake')

      await expectErrorMessage('parent-issue', 'fake')
    })

    it('does not show error message when parent-issue is valid', async () => {
      renderFilter([new ParentIssueFilterProvider()])

      await appendToFilter('parent-issue', 'github/github#4')

      expectNoErrorMessage()
    })

    it('properly validates projects regardless of case', async () => {
      renderFilter([new ParentIssueFilterProvider()])

      await appendToFilter('parent-issue', 'GITHUB/github#4')

      expectNoErrorMessage()
    })
  })

  describe('Project', () => {
    setupProjectsMockApi()

    it('shows error message when project is invalid', async () => {
      renderFilter([new ProjectFilterProvider()])

      await appendToFilter('project', 'fake')

      await expectErrorMessage('project', 'fake')
    })

    it('does not show error message when project value is valid', async () => {
      renderFilter([new ProjectFilterProvider()])

      await appendToFilter('project', 'github/2169')

      expectNoErrorMessage()
    })

    it('properly validates projects regardless of case', async () => {
      renderFilter([new ProjectFilterProvider()])

      await appendToFilter('project', 'GITHUB/2169')

      expectNoErrorMessage()
    })
  })

  describe('Assignee', () => {
    setupUsersMockApi()

    it('shows error message when assignee is invalid', async () => {
      renderFilter([
        new AssigneeFilterProvider({
          showAtMe: true,
          currentUserAvatarUrl: 'https://avatars.githubusercontent.com/u/1?v=4',
          currentUserLogin: 'monalisa',
        }),
      ])

      await appendToFilter('assignee', 'invalid')

      await expectErrorMessage('assignee', 'invalid')
    })

    it('does not show error message when assignee value is valid', async () => {
      renderFilter([
        new AssigneeFilterProvider({
          showAtMe: true,
          currentUserAvatarUrl: 'https://avatars.githubusercontent.com/u/1?v=4',
          currentUserLogin: 'monalisa',
        }),
      ])

      await appendToFilter('assignee', 'dusave')

      expectNoErrorMessage()
    })

    it('properly validates assignees regardless of case', async () => {
      renderFilter([
        new AssigneeFilterProvider({
          showAtMe: true,
          currentUserAvatarUrl: 'https://avatars.githubusercontent.com/u/1?v=4',
          currentUserLogin: 'monalisa',
        }),
      ])

      await appendToFilter('assignee', 'DUSAVE')

      expectNoErrorMessage()
    })

    it('does not show error message when assignee value is @me', async () => {
      renderFilter([
        new AssigneeFilterProvider({
          showAtMe: true,
          currentUserAvatarUrl: 'https://avatars.githubusercontent.com/u/1?v=4',
          currentUserLogin: 'monalisa',
        }),
      ])

      await appendToFilter('assignee', '@me')

      expectNoErrorMessage()
    })

    it('shows error message when assignee is * when showHasValue is false', async () => {
      renderFilter([
        new AssigneeFilterProvider({
          showAtMe: true,
          showHasValue: false,
          currentUserAvatarUrl: 'https://avatars.githubusercontent.com/u/1?v=4',
          currentUserLogin: 'monalisa',
        }),
      ])

      await appendToFilter('assignee', '*')

      await expectErrorMessage('assignee', '*')
    })

    it('does not show error message when assignee is * when showHasValue is true', async () => {
      renderFilter([
        new AssigneeFilterProvider({
          showAtMe: true,
          showHasValue: true,
          currentUserAvatarUrl: 'https://avatars.githubusercontent.com/u/1?v=4',
          currentUserLogin: 'monalisa',
        }),
      ])

      await appendToFilter('assignee', '*')

      expectNoErrorMessage()
    })
  })

  describe('Date', () => {
    const operators = ['', '>', '<', '>=', '<=']

    it.each(operators)('does not show error message when date only is valid with operator: %s', async operator => {
      renderFilter([new CreatedFilterProvider()])

      await appendToFilter('created', `${operator}2012-12-12`)

      expectNoErrorMessage()
    })

    it.each(operators)('does not show error message when date and time is valid with operator: %s', async operator => {
      renderFilter([new CreatedFilterProvider()])

      await appendToFilter('created', `${operator}2017-03-01T15:30:15`)

      expectNoErrorMessage()
    })

    it.each(operators)(
      'does not show error message when date, time and offset is valid with operator: %s',
      async operator => {
        renderFilter([new CreatedFilterProvider()])

        await appendToFilter('created', `${operator}2017-03-01T15:30:15+07:00`)

        expectNoErrorMessage()
      },
    )

    it.each(operators)(
      'does not show error message when date, time and zero offset is valid with operator: %s',
      async operator => {
        renderFilter([new CreatedFilterProvider()])

        await appendToFilter('created', `${operator}2017-03-01T15:30:15Z`)

        expectNoErrorMessage()
      },
    )

    it.each(operators)(
      'does not show error message when date, time and offset is valid with operator: %s',
      async operator => {
        renderFilter([new CreatedFilterProvider()])

        await appendToFilter('created', `${operator}2017-03-01T15:30:15+07:00`)

        expectNoErrorMessage()
      },
    )

    it.each(operators)('shows error message when time is invalid with operator: %s', async operator => {
      renderFilter([new CreatedFilterProvider()])

      await appendToFilter('created', `${operator}2017-03-01T3:30:15pm`)

      await expectErrorMessage('created', `${operator}2017-03-01T3:30:15pm`)
    })

    it.each(operators)('does not show error message when month is a single digit with operator: %s', async operator => {
      renderFilter([new CreatedFilterProvider()])

      await appendToFilter('created', `${operator}2012-1-12`)

      expectNoErrorMessage()
    })

    it.each(operators)('does not show error message when day is a single digit with operator: %s', async operator => {
      renderFilter([new CreatedFilterProvider()])

      await appendToFilter('created', `${operator}2012-12-1`)

      expectNoErrorMessage()
    })

    it.each(operators)(
      'does not show error message when dynamic "today" value is used with operator: %s',
      async operator => {
        renderFilter([new CreatedFilterProvider()])

        await appendToFilter('created', `${operator}@today`)

        expectNoErrorMessage()
      },
    )

    it.each(operators)(
      'does not show error message when dynamic value and day calculations is used with operator: %s',
      async operator => {
        renderFilter([new CreatedFilterProvider()])

        await appendToFilter('created', `${operator}@today+1d`)

        expectNoErrorMessage()
      },
    )

    it.each(operators)(
      'does not show error message when dynamic value and week calculations is used with operator: %s',
      async operator => {
        renderFilter([new CreatedFilterProvider()])

        await appendToFilter('created', `${operator}@today-10w`)

        expectNoErrorMessage()
      },
    )

    it.each(operators)(
      'does not show error message when dynamic value and month calculations is used with operator: %s',
      async operator => {
        renderFilter([new CreatedFilterProvider()])

        await appendToFilter('created', `${operator}@today+1m`)

        expectNoErrorMessage()
      },
    )

    it.each(operators)(
      'does not show error message when dynamic value and month calculations is used with operator: %s',
      async operator => {
        renderFilter([new CreatedFilterProvider()])

        await appendToFilter('created', `${operator}@today+6m`)

        expectNoErrorMessage()
      },
    )

    it.each(operators)(
      'does not show error message when dynamic value and quarter calculations is used with operator: %s',
      async operator => {
        renderFilter([new CreatedFilterProvider()])

        await appendToFilter('created', `${operator}@today-2q`)

        expectNoErrorMessage()
      },
    )

    it.each(operators)(
      'does not show message when dynamic value and year calculations is used with operator: %s',
      async operator => {
        renderFilter([new CreatedFilterProvider()])

        await appendToFilter('created', `${operator}@today+3y`)

        expectNoErrorMessage()
      },
    )

    it.each(operators)(
      'shows error message when dynamic value and invalid calculation operator is used with operator: %s',
      async operator => {
        renderFilter([new CreatedFilterProvider()])

        await appendToFilter('created', `${operator}@today*3d`)

        await expectErrorMessage('created', `${operator}@today*3d`)
      },
    )

    it.each(operators)(
      'shows error message when dynamic value and duplicate calculation operator is used with operator: %s',
      async operator => {
        renderFilter([new CreatedFilterProvider()])

        await appendToFilter('created', `${operator}@today++3d`)

        await expectErrorMessage('created', `${operator}@today++3d`)
      },
    )

    it.each(operators)(
      'shows error message when dynamic value and invalid calculation code is used with operator: %s',
      async operator => {
        renderFilter([new CreatedFilterProvider()])

        await appendToFilter('created', `${operator}@today+3x`)

        await expectErrorMessage('created', `${operator}@today+3x`)
      },
    )

    it.each(operators)('shows error message when invalid dynamic value is used with operator: %s', async operator => {
      renderFilter([new CreatedFilterProvider()])

      await appendToFilter('created', `${operator}@tomorrow`)

      await expectErrorMessage('created', `${operator}@tomorrow`)
    })

    it.each(operators)('shows error message when day is invalid with operator: %s', async operator => {
      renderFilter([new CreatedFilterProvider()])

      await appendToFilter('created', `${operator}2012-12-40`)

      await expectErrorMessage('created', `${operator}2012-12-40`)
    })

    it.each(operators)('shows error message when month is invalid with operator: %s', async operator => {
      renderFilter([new CreatedFilterProvider()])

      await appendToFilter('created', `${operator}2012-30-05`)

      await expectErrorMessage('created', `${operator}2012-30-05`)
    })

    it.each(operators)('shows error message when year is invalid with operator: %s', async operator => {
      renderFilter([new CreatedFilterProvider()])

      await appendToFilter('created', `${operator}20012-01-01`)

      await expectErrorMessage('created', `${operator}20012-01-01`)
    })

    it.each(operators)('shows error message when day is missing with operator: %s', async operator => {
      renderFilter([new CreatedFilterProvider()])

      await appendToFilter('created', `${operator}2012-05`)

      await expectErrorMessage('created', `${operator}2012-05`)
    })

    it.each(operators)('shows error message when delimiter is invalid with operator: %s', async operator => {
      renderFilter([new CreatedFilterProvider()])

      await appendToFilter('created', `${operator}2012.01.01`)

      await expectErrorMessage('created', `${operator}2012.01.01`)
    })

    it.each(operators)('shows error message when date is invalid with operator: %s', async operator => {
      renderFilter([new CreatedFilterProvider()])

      await appendToFilter('created', `${operator}test`)

      await expectErrorMessage('created', `${operator}test`)
    })

    it('does not show error message when valid with operator: ..', async () => {
      renderFilter([new CreatedFilterProvider()])

      await appendToFilter('created', `2012-01-01..2012-02-01`)

      expectNoErrorMessage()
    })
    it('does not show error message when using dynamic value with operator: ..', async () => {
      renderFilter([new CreatedFilterProvider()])

      await appendToFilter('created', `@today..2012-01-01`)

      expectNoErrorMessage()
    })
    it('does not show error message when using wildcard with operator: ..', async () => {
      renderFilter([new CreatedFilterProvider()])

      await appendToFilter('created', `2012-01-01..*`)

      expectNoErrorMessage()
    })
    it('does not show error message when date and time with operator: ..', async () => {
      renderFilter([new CreatedFilterProvider()])

      await appendToFilter('created', `2017-01-01T01:00:00+07:00..2017-03-01T15:30:15Z`)

      expectNoErrorMessage()
    })
    it('shows message when only one value provided with operator: ..', async () => {
      renderFilter([new CreatedFilterProvider()])

      await appendToFilter('created', `2012-01-01..`)

      await expectEmptyValueMessage('created')
    })
    it('shows error message when 2 wildcards are used with operator: ..', async () => {
      renderFilter([new CreatedFilterProvider()])

      await appendToFilter('created', `*..*`)

      await expectErrorMessage('created', `*..*`)
    })
    it('shows error message when additional operators used with operator: ..', async () => {
      renderFilter([new CreatedFilterProvider()])

      await appendToFilter('created', `>2012-01-01..2012-02-02`)

      await expectErrorMessage('created', `>2012-01-01`)
    })
    it('shows error message when only one value is valid with operator: ..', async () => {
      renderFilter([new CreatedFilterProvider()])

      await appendToFilter('created', `2012-01-01..foo`)

      await expectErrorMessage('created', `foo`)
    })
  })

  describe('Focus/Blur', () => {
    it('shows error message when input no longer in focus', async () => {
      renderFilter([new StateFilterProvider()])

      await appendToFilter('state', ' ')

      await expectEmptyValueMessage('state')
    })

    it('shows error message when input focus is returned', async () => {
      renderFilter([new StateFilterProvider()])

      await appendToFilter('state', ' ')

      const input = screen.getByRole('combobox')
      input.focus()

      await expectEmptyValueMessage('state')
    })

    it('shows error message when input blur and sends analytics with error message', async () => {
      renderFilter([new StateFilterProvider()])

      await appendToFilter('state:')

      // eslint-disable-next-line github/no-blur
      screen.getByRole('combobox').blur()

      await expectEmptyValueMessage('state')

      expectAnalyticsEvents({
        type: 'filter.validation_errors',
        target: 'FILTER_VALIDATION_ERRORS',
        data: {
          category: 'filter',
          messages: "Empty value for 'state'",
        },
      })
    })

    it('announces when there is an error message', async () => {
      const region = document.createElement('div')
      region.id = 'js-global-screen-reader-notice'
      region.classList.add('sr-only')
      region.setAttribute('aria-live', 'polite')
      region.setAttribute('data-testid', 'screen-reader-notice')

      document.body.appendChild(region)

      renderFilter([new StateFilterProvider()])

      await appendToFilter('state: state:test')

      // eslint-disable-next-line github/no-blur
      screen.getByRole('combobox').blur()

      await waitFor(() => {
        expect(screen.getByTestId('validation-error-count')).toHaveTextContent('Filter contains 2 issues:')
      })
      expect(screen.getByTestId('validation-error-list')).toHaveTextContent(`Empty value for state`)
      expect(screen.getByTestId('validation-error-list')).toHaveTextContent(`Invalid value test for state`)
      expect(screen.getByTestId('filter-input')).toHaveAttribute(
        'aria-describedby',
        'test-filter-bar-validation-message',
      )
      expect(screen.getByTestId('screen-reader-notice').textContent).toEqual(
        "Filter contains 2 issues: Empty value for 'state'. Invalid value 'test' for 'state'.",
      )
    })

    it('does not show error message when active block has validation warning while still focused', async () => {
      renderFilter([new StateFilterProvider()])

      await appendToFilter('test state:')

      expectNoErrorMessage()
    })

    it('does not mark a value with mismatched quotes as valid', async () => {
      renderFilter([new StateFilterProvider()])

      await appendToFilter('state:"open')
      blurInput(screen)

      await waitFor(() => {
        expect(screen.getByTestId('validation-error-count')).toHaveTextContent('Filter contains 2 issues:')
      })
      expect(screen.getByTestId('validation-error-list')).toHaveTextContent(`Invalid value "open for state`)
      expect(screen.getByTestId('validation-error-list')).toHaveTextContent(`Unbalanced quotation marks`)
      expect(screen.getByTestId('filter-input')).toHaveAttribute(
        'aria-describedby',
        'test-filter-bar-validation-message',
      )
    })
  })
})
