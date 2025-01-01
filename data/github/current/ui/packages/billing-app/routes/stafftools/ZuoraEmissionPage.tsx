import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {Box, Details, useDetails, Spinner, Heading, Text} from '@primer/react'
import {ChevronDownIcon, ChevronLeftIcon, SmileyIcon} from '@primer/octicons-react'
import {formatMoneyDisplay} from '../../utils/money'

import type {ZuoraEmission, EmissionDate} from '../../types/zuora-emissions'
import {RequestState} from '../../enums'
import useZuoraEmissions from '../../hooks/zuora_emissions/use-zuora-emissions'
import {Banner, Blankslate} from '@primer/react/experimental'
import {DatePicker} from '@github-ui/date-picker'
import Layout from '../../components/Layout'
import {Icon} from '@primer/react-brand'
import {useState} from 'react'
import styles from './ZuoraEmissionPage.module.css'

const tableContainerStyle = {
  borderColor: 'border.default',
  borderWidth: 1,
  borderStyle: 'solid',
  fontWeight: 'normal',
  borderRadius: 2,
}

const sharedRowStyles = {
  borderBottomWidth: 1,
  borderBottomStyle: 'solid',
  borderColor: 'border.default',
  p: 3,
}

const tableHeaderStyle = {
  ...sharedRowStyles,
  background: 'var(--bgColor-muted, var(--color-canvas-subtle))',
}

type ZuoraEmissionRowProps = {
  zuoraEmission: ZuoraEmission
  idx: number
}

const ZuoraEmissionRow = ({zuoraEmission, idx}: ZuoraEmissionRowProps) => {
  const {getDetailsProps, open} = useDetails({closeOnOutsideClick: false})

  const rowSummary = (
    <Box key={idx} as="tr" sx={sharedRowStyles}>
      <Box as="td" sx={{py: 3, px: 3}}>
        <Box sx={{display: 'inline-block', verticalAlign: 'middle'}}>
          <Text sx={{fontSize: 1}}>{formatMoneyDisplay(zuoraEmission.usageTotal.gross)}</Text>
        </Box>
      </Box>
      <Box as="td" sx={{py: 3, px: 3}}>
        <Box sx={{display: 'inline-block', verticalAlign: 'middle'}}>
          <Text sx={{fontSize: 1}}>{formatMoneyDisplay(zuoraEmission.usageTotal.discount)}</Text>
        </Box>
      </Box>
      <Box as="td" sx={{py: 3, px: 3}}>
        <Box sx={{display: 'inline-block', verticalAlign: 'middle'}}>
          <Text sx={{fontSize: 1}}>{formatMoneyDisplay(zuoraEmission.usageTotal.net)}</Text>
        </Box>
      </Box>
      <Box as="td" sx={{py: 3, px: 3}}>
        <Box sx={{display: 'inline-block', verticalAlign: 'middle'}}>
          <Text sx={{fontSize: 1}}>{zuoraEmission.usageTotal.quantity}</Text>
        </Box>
      </Box>

      <Box as="td" sx={{py: 3, px: 3}}>
        <Details {...getDetailsProps()} className={styles.Details}>
          <Box
            as={'summary'}
            sx={{p: 2}}
            title={open ? 'Hide Zuora Emission Breakdown' : 'Show Zuora Emission Breakdown'}
            data-testid={'invoice-details'}
          >
            <Icon icon={open ? ChevronDownIcon : ChevronLeftIcon} />
          </Box>
        </Details>
      </Box>
    </Box>
  )

  return (
    <>
      {rowSummary}
      {open && (
        <Box
          key={`${idx}-detail`}
          as="tr"
          sx={{
            ...sharedRowStyles,
            borderTop: 0,
          }}
        >
          <Box as="td" sx={{p: 0}} colSpan={7}>
            <Box as="pre" sx={{p: 3, m: 0, overflowX: 'auto', whiteSpace: 'pre-wrap'}}>
              {JSON.stringify(zuoraEmission, null, 2)}
            </Box>
          </Box>
        </Box>
      )}
    </>
  )
}
export interface ZuoraEmissionPayload {
  is_stafftools_route: boolean
  slug: string
  zuoraEmissions: ZuoraEmission[]
}

export function ZuoraEmissionPage() {
  const payload = useRoutePayload<ZuoraEmissionPayload>()
  const currentTime = new Date()
  const [currentDate, setCurrentDate] = useState<EmissionDate>({
    year: currentTime.getFullYear(),
    month: currentTime.getMonth() + 1,
    day: currentTime.getDate(),
  })
  const {zuoraEmissions, requestState} = useZuoraEmissions({
    enterpriseSlug: payload.slug,
    emissionDate: currentDate,
  })

  return (
    <Layout>
      <header className="Subhead">
        <Heading
          data-testid="zuora-emissions-heading"
          as="h2"
          sx={{font: 'var(--text-subtitle-shorthand)', fontSize: '4'}}
          className="Subhead-heading"
        >
          Zuora Emissions
        </Heading>
      </header>
      <div>
        Choose a usage date to see the emissions for that date. This tool captures the Zuora emission records in
        billing-platform and the record in Zuora Storage Table.
      </div>
      <br />
      <Banner
        title="No Cost Center Zuora Emissions in Table"
        variant="warning"
        description={
          <>
            The emissions found in this table only relate to the parent enterprise and do not include the
            emission&apos;s that were sent for the current enterprise&apos;s cost centers.
          </>
        }
      />
      <br />
      <Box sx={{display: 'flex'}}>
        <Box sx={{flex: 1, marginRight: -200}}>
          <DatePicker
            variant="single"
            dateFormat="long"
            onChange={selection => {
              if (selection) {
                selection = new Date(selection)
                const emissionDate: EmissionDate = {
                  year: selection.getFullYear(),
                  month: selection.getMonth() + 1,
                  day: selection.getDate(),
                }
                setCurrentDate(emissionDate)
              }
            }}
            value={new Date(currentDate.year, currentDate.month - 1, currentDate.day)}
            placeholder="Choose a Usage Date"
          />
        </Box>
      </Box>
      <br />
      <br />
      {zuoraEmissions.length > 0}
      {requestState === RequestState.LOADING && <Spinner />}
      <div>
        <Box sx={tableContainerStyle}>
          <Box as="table" sx={{width: '100%', textAlign: 'left', borderRadius: 2}} data-hpc>
            <thead>
              <tr>
                <Box as="th" sx={tableHeaderStyle}>
                  Gross
                </Box>
                <Box as="th" sx={tableHeaderStyle}>
                  Discount
                </Box>
                <Box as="th" sx={tableHeaderStyle}>
                  Net
                </Box>
                <Box as="th" sx={tableHeaderStyle}>
                  Quantity
                </Box>
                <Box as="th" sx={{...tableHeaderStyle, borderTopRightRadius: 2}}>
                  Details
                </Box>
              </tr>
            </thead>
            <tbody>
              {zuoraEmissions.map((emission, idx) => {
                // eslint-disable-next-line @eslint-react/no-array-index-key
                return <ZuoraEmissionRow zuoraEmission={emission} idx={idx} key={idx} />
              })}
            </tbody>
          </Box>
        </Box>
      </div>
      {zuoraEmissions.length === 0 && requestState === RequestState.IDLE && (
        <div data-testid={'blankslate-container'}>
          <Blankslate>
            <Blankslate.Visual>
              <SmileyIcon size={36} />
            </Blankslate.Visual>
            <Blankslate.Heading>Customer has no Zuora Emissions for this date.</Blankslate.Heading>
            <Blankslate.Description>Please try selecting another date to find emissions</Blankslate.Description>
          </Blankslate>
        </div>
      )}
    </Layout>
  )
}
