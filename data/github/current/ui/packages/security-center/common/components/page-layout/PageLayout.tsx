import {ValidationMessage} from '@github-ui/filter'
import {Box, PageLayout as PrimerPageLayout, Stack} from '@primer/react'
import {useSlots} from '@primer/react/experimental'
import {type PropsWithChildren, useCallback, useState} from 'react'

import Banners from './Banners'
import Content from './Content'
import DatePicker from './DatePicker'
import ExportButton from './ExportButton'
import Filter, {type FilterProps} from './Filter'
import FilterBar from './FilterBar'
import FilterRevert from './FilterRevert'
import Footer from './Footer'
import Header from './Header'
import LimitedRepoWarning from './LimitedRepoWarning'
import Nav from './Nav'
import styles from './PageLayout.module.css'

function PageLayout({children}: PropsWithChildren): JSX.Element {
  const [slots] = useSlots(children, {
    banners: Banners,
    header: Header,
    filterBar: FilterBar,
    exportButton: ExportButton,
    limitedRepoWarning: LimitedRepoWarning,
    nav: Nav,
    content: Content,
    footer: Footer,
  })

  const [validationMessage, setValidationMessage] = useState<string[]>([])

  // Casting this to unknown and then FilterProps because something is going wrong with
  // the typing here. Rather than thinking filter.props is a FilterProps object, it
  // thinks it's a type ('typeof Filter').
  const filterProps = slots.filterBar?.props.filter?.props as unknown as FilterProps

  const onValidation = useCallback(
    (messages: string[]) => {
      setValidationMessage(messages)
      if (filterProps.onValidation) {
        filterProps.onValidation(messages)
      }
    },
    [setValidationMessage, filterProps],
  )

  // Create a new FilterBar component that's identical to the slot,
  // Except we make a new Filter to override onValidation
  let filterBar: JSX.Element | undefined = undefined
  if (slots.filterBar) {
    filterBar = (
      <PageLayout.FilterBar
        filter={<Filter {...filterProps} onValidation={onValidation} />}
        datePicker={slots.filterBar.props.datePicker}
        revert={slots.filterBar.props.revert}
      />
    )
  }

  return (
    <PrimerPageLayout className={styles.PageLayout}>
      <PrimerPageLayout.Header>
        {slots.banners}
        {slots.header}
      </PrimerPageLayout.Header>
      <PrimerPageLayout.Content as="div">
        {(filterBar || slots.exportButton) && (
          <Stack gap="condensed" className="mb-4">
            <Box className="d-flex flex-justify-between" sx={{gap: '1em'}}>
              {filterBar}
              {slots.exportButton}
            </Box>
            {validationMessage.length > 0 && (
              <ValidationMessage messages={validationMessage} id="filter-validation-message" />
            )}
          </Stack>
        )}
        {slots.limitedRepoWarning}
        {slots.nav}
        {slots.content}
      </PrimerPageLayout.Content>
      <PrimerPageLayout.Footer sx={{padding: 'none'}}>{slots.footer}</PrimerPageLayout.Footer>
    </PrimerPageLayout>
  )
}

PageLayout.Banners = Banners
PageLayout.Header = Header
PageLayout.FilterBar = FilterBar
PageLayout.Filter = Filter
PageLayout.DatePicker = DatePicker
PageLayout.FilterRevert = FilterRevert
PageLayout.ExportButton = ExportButton
PageLayout.LimitedRepoWarning = LimitedRepoWarning
PageLayout.Nav = Nav
PageLayout.Content = Content
PageLayout.Footer = Footer

export default PageLayout
