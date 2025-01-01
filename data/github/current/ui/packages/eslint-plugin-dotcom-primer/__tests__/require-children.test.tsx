// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {RuleTester} from '@typescript-eslint/rule-tester'

import noLocatorTestId from '../rules/require-children.js'

const ruleTester = new RuleTester({
  languageOptions: {
    parserOptions: {
      ecmaVersion: 2018,
      sourceType: 'module',
      ecmaFeatures: {
        jsx: true,
      },
    },
  },
})

const options = [
  {
    parent: 'ChartCard',
    child: 'ChartCard.Title',
    message: 'Including <ChartCard.Title> improves chart accessibility.',
    module: '@github-ui/chart-card',
  },
]

const errors = [{messageId: 'requireChildren'}]

// eslint-disable-next-line @typescript-eslint/no-explicit-any
ruleTester.run('require-children', noLocatorTestId as any, {
  valid: [
    {
      name: 'Child',
      code: `
        import {ChartCard} from "@github-ui/chart-card";
        export function App() {
          return (
            <ChartCard>
              <ChartCard.Title>Title</ChartCard.Title>
            </ChartCard>
          );
        }`,
      options,
    },
    {
      name: 'Child in a fragment',
      code: `
        import {ChartCard} from "@github-ui/chart-card";
        export function App() {
          return (
            <ChartCard>
              <>
                <ChartCard.Title>Title</ChartCard.Title>
              </>
            </ChartCard>
          );
        }`,
      options,
    },
    {
      name: 'Child in a truthy expression',
      code: `
        import {ChartCard} from "@github-ui/chart-card";
        export function App() {
          return (
            <ChartCard>
              {true && <ChartCard.Title>Title</ChartCard.Title>}
            </ChartCard>
          );
        }`,
      options,
    },
    // {
    //   // FIXME: Figure out how to handle this
    //   name: 'Child in a variable',
    //   code: `
    //     import {ChartCard} from "@github-ui/chart-card";
    //     export function App() {
    //       const child = <ChartCard.Title>Title</ChartCard.Title>
    //       return (
    //         <ChartCard>
    //           {child}
    //         </ChartCard>
    //       );
    //     }`,
    //   options,
    // },
    // {
    //   // FIXME: Figure out how to handle this
    //   name: 'Child in an array',
    //   code: `
    //     import {ChartCard} from "@github-ui/chart-card";
    //     export function App() {
    //       const children = [<ChartCard.Title>Title</ChartCard.Title>]
    //       return (
    //         <ChartCard>
    //           {...children}
    //         </ChartCard>
    //       );
    //     }`,
    //   options,
    // },
    {
      name: 'Ignore problems from other ChartCard modules',
      code: `
        import {ChartCard} from "@github-ui/chart-card";
        export function App() {
          return <ChartCard />
        }`,
      options: [
        {
          parent: 'ChartCard',
          child: 'ChartCard.Title',
          message: 'Including <ChartCard.Title> improves chart accessibility.',
          module: '../../ChartCard',
        },
      ],
    },
  ],
  invalid: [
    {
      name: 'Missing child',
      code: `
        import {ChartCard} from "@github-ui/chart-card";
        export function App() {
          return <ChartCard />;
        }`,
      options,
      errors,
    },
    {
      name: 'Child in too many fragments',
      code: `
        import {ChartCard} from "@github-ui/chart-card";
        export function App() {
          return (
            <ChartCard>
              <>
                <>
                  <>
                    <>
                      <ChartCard.Title>Title</ChartCard.Title>
                    </>
                  </>
                </>
              </>
            </ChartCard>
          );
        }`,
      options,
      errors,
    },
    {
      name: 'Child in a falsy expression',
      code: `
        import {ChartCard} from "@github-ui/chart-card";
        export function App() {
          return (
            <ChartCard>
              {false && <ChartCard.Title>Title</ChartCard.Title>}
            </ChartCard>
          );
        }`,
      options,
      errors,
    },
    {
      name: 'Child missing from variable',
      code: `
        import {ChartCard} from "@github-ui/chart-card";
        export function App() {
          const child = <></>
          return (
            <ChartCard>
              {child}
            </ChartCard>
          );
        }`,
      options,
      errors,
    },
    {
      name: 'Child missing from array',
      code: `
        import {ChartCard} from "@github-ui/chart-card";
        export function App() {
          const children = [<></>]
          return (
            <ChartCard>
              {...children}
            </ChartCard>
          );
        }`,
      options,
      errors,
    },
  ],
})
