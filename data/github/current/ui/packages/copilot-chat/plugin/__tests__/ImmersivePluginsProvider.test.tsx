import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

import {ImmersivePluginsProvider, usePlugin, usePlugins} from '../ImmersivePluginsProvider'

test('with no plugins registered', () => {
  render(
    <ImmersivePluginsProvider plugins={[]}>
      <PluginContentsTest />
    </ImmersivePluginsProvider>,
  )
  expect(screen.getByTestId(activePluginTestID)).toBeEmptyDOMElement()
  expect(screen.getByTestId(allPluginsTestID)).toBeEmptyDOMElement()
})

test('with a plugin registered, but none active', () => {
  render(
    <ImmersivePluginsProvider plugins={[{id: 'foo', displayName: 'Foo'}]}>
      <PluginContentsTest />
    </ImmersivePluginsProvider>,
  )
  expect(screen.getByTestId(activePluginTestID)).toBeEmptyDOMElement()
  expect(screen.getByTestId(allPluginsTestID)).toHaveTextContent('Name: Foo')
})

test('with a plugin registered, but a non-matching active id', () => {
  render(
    <ImmersivePluginsProvider plugins={[{id: 'foo', displayName: 'Foo'}]}>
      <PluginContentsTest activeID="bar" />
    </ImmersivePluginsProvider>,
  )
  expect(screen.getByTestId(activePluginTestID)).toBeEmptyDOMElement()
  expect(screen.getByTestId(allPluginsTestID)).toHaveTextContent('Name: Foo')
})

test('with a plugin registered and a matching active id', () => {
  render(
    <ImmersivePluginsProvider plugins={[{id: 'foo', displayName: 'Foo'}]}>
      <PluginContentsTest activeID="foo" />
    </ImmersivePluginsProvider>,
  )
  expect(screen.getByTestId(activePluginTestID)).toHaveTextContent('Name: Foo')
  expect(screen.getByTestId(allPluginsTestID)).toHaveTextContent('Name: Foo')
})

test('with multiple plugins registered', () => {
  render(
    <ImmersivePluginsProvider
      plugins={[
        {id: 'foo', displayName: 'Foo'},
        {id: 'bar', displayName: 'Bar'},
        {id: 'baz', displayName: 'Baz'},
      ]}
    >
      <PluginContentsTest activeID="bar" />
    </ImmersivePluginsProvider>,
  )
  expect(screen.getByTestId(activePluginTestID)).toHaveTextContent('Name: Bar')
  expect(screen.getByTestId(allPluginsTestID)).toHaveTextContent('Name: Foo')
  expect(screen.getByTestId(allPluginsTestID)).toHaveTextContent('Name: Bar')
  expect(screen.getByTestId(allPluginsTestID)).toHaveTextContent('Name: Baz')
})

const activePluginTestID = 'active-plugin'
const allPluginsTestID = 'all-plugins'

/** A small component that uses both hooks provided by ImmersivePluginRegistry and puts results in the DOM */
function PluginContentsTest({activeID}: {activeID?: string}) {
  const allPlugins = usePlugins()
  const activePlugin = usePlugin(activeID)

  return (
    <>
      <div data-testid={activePluginTestID}>{activePlugin && <div>Name: {activePlugin.displayName}</div>}</div>
      <div data-testid={allPluginsTestID}>
        {allPlugins.map(p => (
          <div key={p.id}>Name: {p.displayName}</div>
        ))}
      </div>
    </>
  )
}
