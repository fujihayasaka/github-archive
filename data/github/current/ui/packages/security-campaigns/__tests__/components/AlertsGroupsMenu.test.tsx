import {screen} from '@testing-library/react'
import {render as reactRender} from '@github-ui/react-core/test-utils'
import {AlertsGroupsMenu, type AlertsGroupsMenuProps} from '../../components/AlertsGroupsMenu'

const render = async (props: Partial<AlertsGroupsMenuProps> = {}) => {
  return reactRender(<AlertsGroupsMenu group="none" setGroup={jest.fn()} {...props} />, {})
}

it('triggers setGroup when you select a group', async () => {
  const setGroup = jest.fn()
  const {user} = await render({setGroup})

  await user.click(
    screen.getByRole('button', {
      name: 'Group by',
    }),
  )

  await user.click(
    screen.getByRole('menuitemradio', {
      name: 'Repository',
    }),
  )

  expect(setGroup).toHaveBeenCalledWith('repository')
})

it('shows the selected group as selected', async () => {
  const {user} = await render()

  await user.click(
    screen.getByRole('button', {
      name: 'Group by',
    }),
  )

  expect(
    screen.getByRole('menuitemradio', {
      name: 'None',
    }),
  ).toHaveAttribute('aria-checked', 'true')
})
