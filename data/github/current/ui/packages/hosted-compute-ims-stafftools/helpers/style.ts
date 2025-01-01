// Fonts
export const Fonts = {
  PageHeadingFontSize: 4,
  BlankslateTitleFontSize: 3,
  BlankslateSubtitleFontSize: '14px',
}

// Spacing
export const Spacing = {
  StandardPadding: 3,
}

export const pageHeadingStyle = {
  display: 'flex',
  font: 'var(--text-subtitle-shorthand)',
  fontSize: Fonts.PageHeadingFontSize,
}

export const dialogBoxStyle = {
  p: Spacing.StandardPadding,
}

export const tableGapStyle = {
  mt: Spacing.StandardPadding,
  display: 'flex',
  flexDirection: 'column',
  gap: Spacing.StandardPadding,
}

export const breadcrumbLink = {
  cursor: 'pointer',
}

export const formBoxStyle = {
  display: 'flex',
  flexDirection: 'column',
  borderColor: 'border.default',
  rowGap: Spacing.StandardPadding,
}

export const rowStyle = {
  display: 'flex',
  flexDirection: 'row',
  columnGap: Spacing.StandardPadding,
}
