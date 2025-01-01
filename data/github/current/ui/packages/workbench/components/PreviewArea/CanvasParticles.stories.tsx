import type {Meta} from '@storybook/react'

import {CanvasParticles} from './CanvasParticles'

const meta: Meta<typeof WrappedComponent> = {
  title: 'Apps/Workbench/Components/PreviewArea/CanvasParticles',
  component: CanvasParticles,
}

export default meta

const defaultArgs = {}

type WrapperComponentProps = typeof defaultArgs & {}

export const Default = {
  args: defaultArgs,
  render: (args: WrapperComponentProps) => <WrappedComponent {...args} />,
}
const WrappedComponent = () => {
  return <CanvasParticles />
}
