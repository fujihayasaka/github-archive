import type {Meta} from '@storybook/react'
import {http} from 'msw'

import {transformDatabaseToMockResponses} from '../../../contexts/.storybook/WithDatabaseContext'
import {
  withWorkbenchStoreContext,
  workbenchStoreContextDecoratorArgs,
  workbenchStoreContextDecoratorArgTypes,
} from '../../../contexts/.storybook/WithWorkbenchStoreContext'
import {DatabaseProvider} from '../../../contexts/DatabaseContext'
import {DATABASE_DEFAULT} from '../../../utilities/parse-data'
import {DataPanel} from './DataPanel'

const MOCK_DATABASE_ID = 'mockDatabaseId'
const databaseDefault = structuredClone(DATABASE_DEFAULT)

export default {
  title: 'Apps/Workbench/Components/SidePanel/Panels/DataPanel',
  component: DataPanel,
  argTypes: {
    ...workbenchStoreContextDecoratorArgTypes,
  },
  args: {
    ...workbenchStoreContextDecoratorArgs,
  },
  decorators: [withWorkbenchStoreContext],
  render: () => {
    return (
      <div
        style={{
          display: 'flex',
          flexDirection: 'column',
          background: 'var(--bgColor-default)',
          overflow: 'hidden',
          width: '100%',
          maxWidth: '250px',
          minWidth: '320px',
          height: '100%',
          transition: 'transform 300ms var(--easing-easeOut)',
          transform: 'translateX(0)',
          '--panel-nav-height': '48px',
        }}
      >
        <DatabaseProvider runtimePermanentName={MOCK_DATABASE_ID}>
          <DataPanel />
        </DatabaseProvider>
      </div>
    )
  },
} satisfies Meta<typeof DataPanel>

export const Default = {
  args: {
    workbenchReadOnly: false,
  },
  parameters: {
    msw: {
      handlers: transformDatabaseToMockResponses(databaseDefault, MOCK_DATABASE_ID),
    },
  },
}

export const NoData = {
  parameters: {
    msw: {
      handlers: [transformDatabaseToMockResponses([], MOCK_DATABASE_ID)],
    },
  },
}

export const FailedFetch = {
  parameters: {
    msw: {
      handlers: [
        http.get(`/copilot/spark/runtime/data/${MOCK_DATABASE_ID}`, async () => {
          await new Promise(resolve => setTimeout(resolve, 1000))
          throw new Error('Intentionally fail')
        }),
      ],
    },
  },
}
