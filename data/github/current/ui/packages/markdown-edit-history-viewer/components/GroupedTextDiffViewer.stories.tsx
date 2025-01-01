import {Box, Textarea} from '@primer/react'
import type {Meta} from '@storybook/react'
import {useState} from 'react'

import {GroupedTextDiffViewer} from './GroupedTextDiffViewer'

type WrappedDiffViewerWithInputsProps = {
  initialBefore: string
  initialAfter: string
}

const WrappedDiffViewerWithInputs = ({initialBefore, initialAfter}: WrappedDiffViewerWithInputsProps) => {
  const [before, setBefore] = useState(initialBefore)
  const [after, setAfter] = useState(initialAfter)

  return (
    <Box sx={{flexDirection: 'column', gap: 2, display: 'flex'}}>
      <>
        <Box as="label" htmlFor="before-comparison" sx={{display: 'block'}}>
          Previous text:
        </Box>
        <Textarea
          id="before-comparison"
          value={before}
          onChange={e => setBefore(e.target.value)}
          sx={{width: '400px'}}
        />
      </>
      <>
        <Box as="label" htmlFor="after-comparison" sx={{display: 'block'}}>
          Current text:
        </Box>
        <Textarea id="after-comparison" value={after} onChange={e => setAfter(e.target.value)} sx={{width: '400px'}} />
      </>
      <>
        <div>GroupedTextDiffViewer Output:</div>
        <GroupedTextDiffViewer before={before} after={after} />
      </>
    </Box>
  )
}

const meta = {
  title: 'GroupedTextDiffViewer',
  component: GroupedTextDiffViewer,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
  argTypes: {},
} satisfies Meta<typeof GroupedTextDiffViewer>

export default meta

const initialBefore = `Hello all

this is a great test strang!

and so this is before text`

const initialAfter = `Hello all

this is a great test string!

but then this is after text`

export const TextDiffViewerExample = {
  args: {},
  render: () => <WrappedDiffViewerWithInputs initialBefore={initialBefore} initialAfter={initialAfter} />,
}
