export const Constants = {
  stafftoolPageTitle: 'Hosted Compute Image Management',
  blankslateTitle: 'Welcome to IMS Stafftools',
  blankslateDescription: 'Coming soon!',
  curatedImagesTabTitle: 'Curated images',
  marketplaceImagesTableTitle: 'Marketplace images',
  nameValidation:
    'Must be 1-100 characters, and may only contain letters, numbers, spaces, parentheses, periods (.), hyphens (-), and underscores (_).',
  featureFlagValidation: 'Must start with "ims_" prefix and may contain only letters, numbers and underscores',
}

export const CuratedImagesTableConstants = {
  tableTitle: 'Images',
  newAction: 'New image',
  editAction: 'Edit image',
  deleteAction: 'Delete image',
  viewImageVersions: 'View image versions',
  failedDeleteHasImageVersions: 'Image has image versions',
  failedDeleteReferencedByPointer: 'Image is referenced by pointer',
  blankStateTitle: 'No curated images found',
  blankStateSubtitle: 'Curated images will be listed here',
}

export const CuratedImagePointersTableConstants = {
  tableTitle: 'Pointers',
  newAction: 'New pointer',
  editAction: 'Edit pointer',
  deleteAction: 'Delete pointer',
  blankStateTitle: 'No curated image pointers found',
  blankStateSubtitle: 'Curated image pointers will be listed here',
}

export const CuratedImageDialogConstants = {
  New: {
    dialogTitle: 'New curated image',
    submitButton: 'Create',
    successBanner: 'Image has been created',
  },
  Edit: {
    dialogTitle: 'Edit curated image',
    submitButton: 'Update',
    successBanner: 'Image has been updated',
  },
  Delete: {
    dialogTitle: 'Delete curated image',
    submitButton: 'Delete',
    confirmation: 'Are you sure that you want to delete curated image?',
    successBanner: 'Image has been deleted',
  },
}

export const CuratedImagePointerDialogConstants = {
  New: {
    dialogTitle: 'New curated image pointer',
    submitButton: 'Create',
    successBanner: 'Image pointer has been created',
  },
  Edit: {
    dialogTitle: 'Edit curated image pointer',
    submitButton: 'Update',
    successBanner: 'Image pointer has been updated',
  },
  Delete: {
    dialogTitle: 'Delete curated image pointer',
    submitButton: 'Delete',
    confirmation: 'Are you sure that you want to delete curated image pointer?',
    successBanner: 'Image pointer has been deleted',
  },
}

export const CuratedImageVersionDialogConstants = {
  Update: {
    successBanner: 'Image version has been updated',
  },
  Delete: {
    dialogTitle: 'Delete curated image version',
    submitButton: 'Delete',
    confirmation: 'Are you sure that you want to delete curated image version?',
    successBanner: 'Image version deletion has been started',
  },
}

export const CuratedImageVersionStateDetailsDialogConstants = {
  dialogTitle: 'Image version state details',
  stateTitle: 'State: ',
  lastUpdateTitle: 'Last update: ',
  stateDetailsTitle: 'State details: ',
}
