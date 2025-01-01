import {Panel} from './playground-manager'

export const parametersConfig = {
  controls: {expanded: true, sort: 'alpha'},
  viewport: {
    viewports: {
      // https://github.com/primer/react/blob/b1950f572954f504d91c49cc16220be91ecfc38e/packages/react/src/hooks/useResponsiveValue.ts
      narrow: {name: 'narrow', styles: {width: '767px', height: '600px'}},
      regular: {name: 'regular', styles: {width: '1000px', height: '750px'}},
      wide: {name: 'wide', styles: {width: '1400px', height: '900px'}},
    },
    defaultViewport: 'regular',
  },
}

export const panelPositionArgType = {
  control: 'radio',
  description: `${Panel.Main} = main, ${Panel.Side} = side`,
  options: [Panel.Main, Panel.Side],
} as const
