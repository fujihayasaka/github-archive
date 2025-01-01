import {Box, Button, Heading, ProgressBar, SegmentedControl, Text} from '@primer/react'
import {Links} from '../../components/Links'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import type {RoutePayload} from './types'
import {Banner} from '@primer/react/experimental'
import {BorderBox} from './components/BorderBox'
import {DataSourceItem} from './components/DataSourceItem'
import {theme} from '../../theme'

type TelemetryDatum = {
  name: string
  value: string
}

const telemetryData: TelemetryDatum[] = [
  {name: 'Active users', value: '1,000'},
  {name: 'Interactions', value: '1,000'},
  {name: 'Time period', value: '12 months'},
]

type RepoDatum = {
  name: string
  progressPercent: number
  value: string
}

const repoData: RepoDatum[] = [
  {name: 'RepositoryName', progressPercent: 78, value: '78 kB'},
  {name: 'RepositoryName2', progressPercent: 66, value: '36 kB'},
  {name: 'RepositoryName3', progressPercent: 45, value: '12.8 kB'},
]

export function Assessment() {
  const routePayload = useRoutePayload<RoutePayload>()

  return (
    <Box
      sx={{
        display: 'flex',
        flexDirection: 'column',
        gap: '12px',
        justifyContent: 'center',
        mt: '40px',
        width: '100%',
      }}
    >
      <Box sx={{display: 'flex', flexDirection: 'column', gap: '8px', justifyContent: 'center', width: '100%'}}>
        <Heading as="h3" sx={{color: theme.color.fgDefault, ...theme.typography.deprecated.heading.h3}}>
          Your training data assessment
        </Heading>

        <Text sx={{color: theme.color.fgMuted, ...theme.typography.deprecated.textNormal}}>
          Review the data you selected to train your fine tuned model before starting the training process.
        </Text>
      </Box>

      <Banner
        hideTitle
        description="You’re ready to train your fine tuned model! Next steps will be to test and deploy your model."
        title="You’re ready!"
        variant="success"
      />

      <BorderBox sx={{p: 0}}>
        <Box
          sx={{
            display: 'flex',
            flexDirection: 'column',
            gap: '12px',
            justifyContent: 'center',
            px: '20px',
            py: '16px',
            width: '100%',
          }}
        >
          <Box sx={{display: 'flex', flexDirection: 'column', gap: '8px', justifyContent: 'center', width: '100%'}}>
            <Heading as="h3" sx={{color: theme.color.fgDefault, ...theme.typography.title.small}}>
              Data source overview
            </Heading>

            <Text sx={{color: theme.color.fgDefault, fontSize: '14px', lineHeight: '22px'}}>
              Your data is under the maximum limit (100 GB) and above the minimum limit (20 GB) needed for a meaningful
              training data set.
            </Text>
          </Box>

          <Text sx={{color: theme.color.fgMuted, fontSize: '14px', lineHeight: '22px'}}>90 GB / 100 GB</Text>
        </Box>

        <DataSourceItem type="telemetry-data" />

        <DataSourceItem type="repository-data" />
      </BorderBox>

      <BorderBox sx={{p: 0}}>
        <Box
          sx={{
            borderBottom: theme.border,
            display: 'flex',
            flexDirection: 'column',
            gap: '12px',
            justifyContent: 'center',
            px: '20px',
            py: '16px',
            width: '100%',
          }}
        >
          <Box sx={{display: 'flex', flexDirection: 'column', gap: '8px', justifyContent: 'center', width: '100%'}}>
            <Heading as="h4" sx={{color: theme.color.fgDefault, ...theme.typography.title.small}}>
              Telemetry data
            </Heading>

            <Text sx={{color: theme.color.fgDefault, fontSize: '14px', lineHeight: '22px'}}>
              Your telemetry data covers 85% of the recommended 100%, with 102,596 events recorded. This provides a
              strong foundation for training your custom model.
            </Text>
          </Box>

          <Text sx={{color: theme.color.fgMuted, fontSize: '14px', lineHeight: '22px'}}>40 GB / 100 GB</Text>
        </Box>

        <Box sx={{display: 'flex', flexDirection: 'column', px: '20px', py: '12px', width: '100%'}}>
          {telemetryData.map((datum, i) => (
            <Box
              key={datum.name}
              sx={{
                alignItems: 'center',
                borderBottom: i === telemetryData.length - 1 ? undefined : '1px solid var(--borderColor-default)',
                display: 'flex',
                height: '36px',
                justifyContent: 'space-between',
                width: '100%',
              }}
            >
              <Text sx={{color: theme.color.fgDefault, ...theme.typography.body.smallBold}}>{datum.name}</Text>
              <Text sx={{color: theme.color.fgDefault, ...theme.typography.body.small}}>{datum.value}</Text>
            </Box>
          ))}
        </Box>
      </BorderBox>

      <BorderBox sx={{p: 0}}>
        <Box
          sx={{
            display: 'flex',
            flexDirection: 'column',
            gap: '12px',
            justifyContent: 'center',
            px: '20px',
            py: '16px',
            width: '100%',
          }}
        >
          <Box sx={{display: 'flex', flexDirection: 'column', gap: '8px', justifyContent: 'center', width: '100%'}}>
            <Heading as="h4" sx={{color: theme.color.fgDefault, ...theme.typography.title.small}}>
              Repository data
            </Heading>

            <Text sx={{color: theme.color.fgDefault, fontSize: '14px', lineHeight: '22px'}}>
              Selected repositories provide balanced coverage of your codebase.
            </Text>
          </Box>

          <Text sx={{color: theme.color.fgMuted, fontSize: '14px', lineHeight: '22px'}}>30 GB / 100 GB</Text>
        </Box>

        <Box
          sx={{
            borderTop: theme.border,
            display: 'flex',
            flexDirection: 'column',
            gap: '12px',
            justifyContent: 'center',
            px: '20px',
            py: '16px',
            width: '100%',
          }}
        >
          <SegmentedControl
            aria-label="Repository data view options"
            fullWidth={{narrow: true}}
            size="small"
            sx={{width: 'fit-content'}}
          >
            <SegmentedControl.Button defaultSelected>Top repositories</SegmentedControl.Button>
            <SegmentedControl.Button>Languages</SegmentedControl.Button>
          </SegmentedControl>

          <Box sx={{display: 'flex', flexDirection: 'column', width: '100%'}}>
            {repoData.map((datum, i) => (
              <Box
                key={datum.name}
                sx={{
                  alignItems: 'center',
                  borderBottom: i === telemetryData.length - 1 ? undefined : '1px solid var(--borderColor-default)',
                  display: 'flex',
                  height: '40px',
                  justifyContent: 'space-between',
                  width: '100%',
                }}
              >
                <Text sx={{color: theme.color.fgDefault, ...theme.typography.body.smallBold, minWidth: '185px'}}>
                  {datum.name}
                </Text>
                <ProgressBar bg="neutral.emphasis" progress={datum.progressPercent} sx={{width: '100%'}} />
                <Text
                  sx={{
                    color: theme.color.fgDefault,
                    ...theme.typography.body.small,
                    minWidth: '115px',
                    textAlign: 'right',
                  }}
                >
                  {datum.value}
                </Text>
              </Box>
            ))}
          </Box>
        </Box>
      </BorderBox>

      <BorderBox sx={{display: 'flex', flexDirection: 'column', gap: '12px', px: '20px', py: '16px', width: '100%'}}>
        <Box sx={{display: 'flex', flexDirection: 'column', gap: '8px', justifyContent: 'center', width: '100%'}}>
          <Heading as="h4" sx={{color: theme.color.fgDefault, ...theme.typography.title.small}}>
            Cost estimate
          </Heading>

          <Text sx={{color: theme.color.fgDefault, fontSize: '14px', lineHeight: '22px'}}>
            We&apos;ve analyzed your selected training data sources and have prepared the following cost estimate for
            creating your custom model.
          </Text>
        </Box>

        <Banner
          hideTitle
          description="Your training cost will be $1,570 based on 950,000 tokens. Monthly hosting fees depend on usage."
          title="Training cost estimate"
          variant="info"
        />
      </BorderBox>

      <Box sx={{display: 'flex', justifyContent: 'flex-end', gap: '12px', width: '100%'}}>
        <Button variant="default">Edit selections</Button>
        <Button variant="primary">Start training</Button>
      </Box>

      <Links {...routePayload} />
    </Box>
  )
}
