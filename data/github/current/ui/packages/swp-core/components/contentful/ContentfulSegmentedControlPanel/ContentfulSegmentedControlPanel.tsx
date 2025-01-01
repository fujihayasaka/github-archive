import {useState} from 'react'
import {Grid} from '@primer/react-brand'
import styles from './ContentfulSegmentedControlPanel.module.css'
import type {SegmentedControlPanel} from '../../../schemas/contentful/contentTypes/segmentedControlPanel'
import {ContentfulFlexSection} from '../ContentfulFlexSection/ContentfulFlexSection'

export type ContentfulSegmentedControlPanelProps = {
  component: SegmentedControlPanel
}
export function ContentfulSegmentedControlPanel({component}: ContentfulSegmentedControlPanelProps) {
  const [selectedItem, setSelectedItem] = useState(0)
  const handleSelectedItemChanged = (index: number) => {
    setSelectedItem(index)
  }

  return (
    <Grid className={styles.segmentedControlPanelGrid}>
      <Grid.Column span={12}>
        <div className={styles.segmentedControlContainer} role="tablist" aria-label={component.fields?.ariaLabel}>
          {component.fields.panelItems.map((item, index) => (
            <button
              key={item.sys.id}
              className={`${styles.segmentedControlButton} ${selectedItem === index ? styles.active : ''}`}
              id={`${item.sys.id}-tab`}
              onClick={() => handleSelectedItemChanged(index)}
              role="tab"
              aria-selected={selectedItem === index}
              aria-controls={`${item.sys.id}-tab-panel`}
            >
              {item.fields.label}
            </button>
          ))}
        </div>
      </Grid.Column>
      <Grid.Column span={12}>
        {component.fields.panelItems.map((item, index) => (
          <div
            key={item.sys.id}
            id={`${item.sys.id}-tab-panel`}
            role="tabpanel"
            aria-labelledby={`${item.sys.id}-tab`}
            hidden={selectedItem !== index}
          >
            {item.fields.flexSections.map(section => (
              <div key={section.sys.id}>
                <ContentfulFlexSection component={section} />
              </div>
            ))}
          </div>
        ))}
      </Grid.Column>
    </Grid>
  )
}
