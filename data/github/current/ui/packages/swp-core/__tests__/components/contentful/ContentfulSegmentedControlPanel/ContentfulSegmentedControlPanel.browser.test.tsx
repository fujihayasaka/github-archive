import {BLOCKS} from '@contentful/rich-text-types'
import {screen} from '@testing-library/react'

import {render} from '@github-ui/react-core/test-utils'
import {describe, expect, it} from '@github-ui/tests'

import {ContentfulSegmentedControlPanel} from '../../../../components/contentful/ContentfulSegmentedControlPanel/ContentfulSegmentedControlPanel'
import type {SegmentedControlPanel} from '../../../../schemas/contentful/contentTypes/segmentedControlPanel'

const mockComponent: SegmentedControlPanel = {
  sys: {
    id: 'segmentedControlPanel-0',
    contentType: {sys: {id: 'segmentedControlPanel'}},
  },
  fields: {
    ariaLabel: 'Segmented Control Panel Label',
    panelItems: [
      {
        sys: {
          id: 'segmentedControlPanelItem-0',
          contentType: {sys: {id: 'segmentedControlPanelItem'}},
        },
        fields: {
          label: 'For Tab 0',
          flexSections: [
            {
              sys: {
                id: 'flexSection-0',
                contentType: {sys: {id: 'flexSection'}},
              },
              fields: {
                introContent: {
                  sys: {
                    id: 'primerComponentSectionIntro-0',
                    contentType: {
                      sys: {
                        id: 'primerComponentSectionIntro',
                      },
                    },
                  },
                  fields: {
                    align: 'center',
                    fullWidth: false,
                    heading: {
                      nodeType: BLOCKS.DOCUMENT,
                      data: {},
                      content: [
                        {
                          nodeType: BLOCKS.PARAGRAPH,
                          data: {},
                          content: [
                            {
                              nodeType: 'text',
                              value: 'Panel 0 Section Intro',
                              marks: [],
                              data: {},
                            },
                          ],
                        },
                      ],
                    },
                  },
                },
              },
            },
          ],
        },
      },
      {
        sys: {
          id: 'segmentedControlPanelItem-1',
          contentType: {sys: {id: 'segmentedControlPanelItem'}},
        },
        fields: {
          label: 'For Tab 1',
          flexSections: [
            {
              sys: {
                id: 'flexSection-1',
                contentType: {sys: {id: 'flexSection'}},
              },
              fields: {
                introContent: {
                  sys: {
                    id: 'primerComponentSectionIntro-1',
                    contentType: {
                      sys: {
                        id: 'primerComponentSectionIntro',
                      },
                    },
                  },
                  fields: {
                    align: 'center',
                    fullWidth: false,
                    heading: {
                      nodeType: BLOCKS.DOCUMENT,
                      data: {},
                      content: [
                        {
                          nodeType: BLOCKS.PARAGRAPH,
                          data: {},
                          content: [
                            {
                              nodeType: 'text',
                              value: 'Panel 1 Section Intro',
                              marks: [],
                              data: {},
                            },
                          ],
                        },
                      ],
                    },
                  },
                },
              },
            },
          ],
        },
      },
    ],
  },
}

describe('ContentfulSegmentedControlPanel', () => {
  it('renders tablist and correct number of tab buttons with labels', () => {
    render(<ContentfulSegmentedControlPanel component={mockComponent} />)
    const tablist = screen.getByRole('tablist')
    expect(tablist).toBeInTheDocument()
    expect(tablist).toHaveAttribute('aria-label', 'Segmented Control Panel Label')
    const tabs = screen.getAllByRole('tab')
    expect(tabs).toHaveLength(2)
    expect(tabs[0]).toHaveTextContent('For Tab 0')
    expect(tabs[1]).toHaveTextContent('For Tab 1')
  })

  it('selects first tab by default and shows only its panel', () => {
    render(<ContentfulSegmentedControlPanel component={mockComponent} />)
    // Check the default selected tab
    const tabs = screen.getAllByRole('tab')
    expect(tabs[0]).toHaveAttribute('aria-selected', 'true')
    expect(tabs[1]).toHaveAttribute('aria-selected', 'false')

    // Check the default selected panel
    const panels = screen.getAllByRole('tabpanel', {hidden: true})
    expect(panels[0]).toBeVisible()
    expect(panels[1]).not.toBeVisible()

    // Check the content of the selected panel
    const flexSectionContent0 = screen.getByText('Panel 0 Section Intro')
    const flexSectionContent1 = screen.queryByText('Panel 1 Section Intro')
    expect(flexSectionContent0).toBeInTheDocument()
    expect(flexSectionContent0).toBeVisible()
    expect(flexSectionContent1).toBeInTheDocument()
    expect(flexSectionContent1).not.toBeVisible()
  })

  it('selects second tab when clicked and shows its panel', async () => {
    const {user} = render(<ContentfulSegmentedControlPanel component={mockComponent} />)
    const tabs = screen.getAllByRole('tab')
    if (tabs[1]) await user.click(tabs[1])

    // Check the selected tab
    expect(tabs[0]).toHaveAttribute('aria-selected', 'false')
    expect(tabs[1]).toHaveAttribute('aria-selected', 'true')

    // Check the default selected panel
    const panels = screen.getAllByRole('tabpanel', {hidden: true})
    expect(panels[0]).not.toBeVisible()
    expect(panels[1]).toBeVisible()

    // Check the content of the selected panel
    const flexSectionContent0 = screen.getByText('Panel 0 Section Intro')
    const flexSectionContent1 = screen.queryByText('Panel 1 Section Intro')
    expect(flexSectionContent0).toBeInTheDocument()
    expect(flexSectionContent0).not.toBeVisible()
    expect(flexSectionContent1).toBeInTheDocument()
    expect(flexSectionContent1).toBeVisible()
  })

  it('sets correct aria attributes for tabs and panels', () => {
    render(<ContentfulSegmentedControlPanel component={mockComponent} />)
    const tabs = screen.getAllByRole('tab')
    const panels = screen.getAllByRole('tabpanel', {hidden: true})

    //Check the IDs and aria attributes for first SegmentedControlPanelItem
    expect(tabs[0]?.id).toBe('segmentedControlPanelItem-0-tab')
    expect(tabs[0]).toHaveAttribute('aria-controls', 'segmentedControlPanelItem-0-tab-panel')
    expect(panels[0]?.id).toBe('segmentedControlPanelItem-0-tab-panel')
    expect(panels[0]).toHaveAttribute('aria-labelledby', 'segmentedControlPanelItem-0-tab')

    //Check the IDs and aria attributes for second SegmentedControlPanelItem
    expect(tabs[1]?.id).toBe('segmentedControlPanelItem-1-tab')
    expect(tabs[1]).toHaveAttribute('aria-controls', 'segmentedControlPanelItem-1-tab-panel')
    expect(panels[1]?.id).toBe('segmentedControlPanelItem-1-tab-panel')
    expect(panels[1]).toHaveAttribute('aria-labelledby', 'segmentedControlPanelItem-1-tab')
  })

  it('renders nothing if panelItems is empty', () => {
    const emptyComponent = {
      ...mockComponent,
      fields: {...mockComponent.fields, panelItems: []},
    }
    render(<ContentfulSegmentedControlPanel component={emptyComponent} />)
    expect(screen.queryByRole('tab')).not.toBeInTheDocument()
    expect(screen.queryByRole('tabpanel')).not.toBeInTheDocument()
  })

  it('renders multiple flexSections if present', () => {
    const multiSectionComponent = {
      ...mockComponent,
      fields: {
        ...mockComponent.fields,
        panelItems: [
          {
            ...mockComponent.fields.panelItems[0],
            fields: {
              ...mockComponent.fields.panelItems[0]?.fields,
              flexSections: [
                ...(mockComponent.fields.panelItems[0]?.fields!.flexSections ?? []),
                {
                  sys: {
                    id: 'flexSection-2',
                    contentType: {sys: {id: 'flexSection'}},
                  },
                  fields: {
                    introContent: {
                      sys: {
                        id: 'primerComponentSectionIntro-2',
                        contentType: {
                          sys: {
                            id: 'primerComponentSectionIntro',
                          },
                        },
                      },
                      fields: {
                        align: 'center',
                        fullWidth: false,
                        heading: {
                          nodeType: BLOCKS.DOCUMENT,
                          data: {},
                          content: [
                            {
                              nodeType: BLOCKS.PARAGRAPH,
                              data: {},
                              content: [
                                {
                                  nodeType: 'text',
                                  value: 'Panel 2 Section Intro',
                                  marks: [],
                                  data: {},
                                },
                              ],
                            },
                          ],
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
          mockComponent.fields.panelItems[1],
        ],
      },
    } as SegmentedControlPanel
    render(<ContentfulSegmentedControlPanel component={multiSectionComponent} />)
    const segmentedControlPanelItem0Section0 = screen.getByText('Panel 0 Section Intro')
    const segmentedControlPanelItem0Section2 = screen.getByText('Panel 2 Section Intro')
    expect(segmentedControlPanelItem0Section0).toBeInTheDocument()
    expect(segmentedControlPanelItem0Section2).toBeInTheDocument()
    expect(segmentedControlPanelItem0Section0).toBeVisible()
    expect(segmentedControlPanelItem0Section2).toBeVisible()
  })

  it('does not crash if ariaLabel is missing', () => {
    const noAriaComponent = {
      ...mockComponent,
      fields: {...mockComponent.fields, ariaLabel: undefined},
    }
    render(<ContentfulSegmentedControlPanel component={noAriaComponent} />)
    const tablist = screen.getByRole('tablist')
    expect(tablist).toBeInTheDocument()
    expect(tablist).not.toHaveAttribute('aria-label')

    const tabs = screen.getAllByRole('tab')
    expect(tabs[0]).toHaveAttribute('aria-selected', 'true')
    expect(tabs[1]).toHaveAttribute('aria-selected', 'false')
    const panels = screen.getAllByRole('tabpanel')
    expect(panels[0]).toBeVisible()
  })
})
