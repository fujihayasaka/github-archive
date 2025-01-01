import type {Meta, StoryObj} from '@storybook/react'

import type {DiffAnnotation} from '../types'
import type {AnnotationDialogProps} from './AnnotationDialog'
import {AnnotationDialog} from './AnnotationDialog'

const meta: Meta<typeof AnnotationDialog> = {
  title: 'Apps/React Shared/Conversations/AnnotationDialog',
  component: AnnotationDialog,
}

type Story = StoryObj<typeof AnnotationDialog>

export const Story = {
  argTypes: {
    annotationLevel: {
      options: ['FAILURE', 'WARNING', 'NOTICE'],
      control: {type: 'select'},
    },
  },
  args: {
    id: 1,
    annotationLevel: 'FAILURE',
    startLine: 1,
    endLine: 1,
    message: 'my annotation message',
    path: 'file.md',
    title: 'check annotation title',
    checkRun: {
      name: 'check-run-name',
      detailsUrl: 'http://github.localhost/monalisa/smile/actions/runs/1/job/1',
    },
    checkSuiteName: 'check-suite-name',
    appAvatarAltText: 'check-suite-app-name avatar image',
    appAvatarUrl: 'http://alambic.github.localhost/avatars/u/2?size=48',
    onClose: () => {},
    markerNavigationImplementation: {
      incrementActiveMarker: () => {},
      decrementActiveMarker: () => {},
      filteredMarkers: [],
      onActivateGlobalMarkerNavigation: () => {},
      activeGlobalMarkerID: undefined,
    },
  },
  render: ({
    onClose,
    markerNavigationImplementation,
    ...rest
  }: Pick<AnnotationDialogProps, 'markerNavigationImplementation' | 'onClose'> & DiffAnnotation) => (
    <AnnotationDialog
      annotation={rest}
      onClose={onClose}
      markerNavigationImplementation={markerNavigationImplementation}
    />
  ),
}

export default meta
