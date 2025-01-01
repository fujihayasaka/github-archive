import type {ResourcesSections, SectionsShown, ViewContext} from './types/integration-permission-selector'
import {useCallback, useEffect, useState, useRef} from 'react'

export interface IntegrationPermissionSelectorProps {
  exampleMessage: string
  resources: ResourcesSections
  view: ViewContext
  currentTarget: unknown
  showSections: SectionsShown
}

export function IntegrationPermissionSelector(props: IntegrationPermissionSelectorProps) {
  const [sections, setSectionShown] = useState<SectionsShown>(props.showSections)
  const sectionsRef = useRef(sections)

  const resetPermissions = () => {
    // console.log('Resetting permissions...')
  }

  const toggleRepoPermissionVisibility = useCallback(
    (id: string) => {
      setSectionShown(prev => ({
        ...prev,
        repository: id !== 'install_target_none',
      }))
    },
    [setSectionShown],
  )

  useEffect(() => {
    sectionsRef.current = sections
  }, [sections])

  useEffect(() => {
    const radioButtons = document.querySelectorAll('input[type="radio"].js-installation-repositories-radio')

    function handleRadioChange(event: Event) {
      const target = event.target as HTMLInputElement
      const id = target.id

      resetPermissions()
      toggleRepoPermissionVisibility(id)
    }

    for (const radio of radioButtons) {
      radio.addEventListener('change', handleRadioChange)
    }

    return () => {
      for (const radio of radioButtons) {
        radio.removeEventListener('change', handleRadioChange)
      }
    }
  }, [toggleRepoPermissionVisibility])

  return (
    <>
      <div style={{padding: '20px', backgroundColor: '#f0f0f0', color: '#333'}}>
        <h1>React Component: Integration Permission Selector</h1>
        <article>{props.exampleMessage}</article>
      </div>
    </>
  )
}
