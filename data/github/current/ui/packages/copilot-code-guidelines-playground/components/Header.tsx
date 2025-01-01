import {ArrowLeftIcon} from '@primer/octicons-react'
import {IconButton, Label, UnderlineNav} from '@primer/react'
import {usePlaygroundContext} from '../PlaygroundContext'

export default function Header() {
  const {currentCodingGuideline, indexPath, showTabBar, occurrencesPath} = usePlaygroundContext()
  const headerTitle = currentCodingGuideline.id ? 'Edit coding guideline' : 'New coding guideline'

  return (
    <>
      <div className="d-flex flex-items-left flex-md-items-center flex-justify-between gap-3 flex-column flex-sm-row">
        <div className="d-flex flex-items-center gap-1">
          <IconButton
            as="a"
            icon={ArrowLeftIcon}
            aria-label="Back to coding guidelines"
            size="small"
            variant="invisible"
            href={indexPath}
          />
          <h1 className="text-semibold h2">{headerTitle}</h1>
          <Label variant="success" className="ml-1 mt-1">
            Preview
          </Label>
        </div>
      </div>
      {!!currentCodingGuideline.id && showTabBar && (
        <UnderlineNav aria-label="Coding Guideline">
          <UnderlineNav.Item key="Edit" href="#" aria-current="page">
            Edit
          </UnderlineNav.Item>
          <UnderlineNav.Item key="Occurrences" href={occurrencesPath}>
            Occurrences
          </UnderlineNav.Item>
        </UnderlineNav>
      )}
    </>
  )
}
