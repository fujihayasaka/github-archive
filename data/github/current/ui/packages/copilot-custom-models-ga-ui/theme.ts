// These variables align with Figma's color palette and typography styles.
export const theme = {
  border: '1px solid var(--borderColor-default)',
  color: {
    bgInset: 'var(--bgColor-inset)',
    fgAccent: 'var(--fgColor-accent)',
    fgDefault: 'var(--fgColor-default)',
    fgMuted: 'var(--fgColor-muted)',
  },
  typography: {
    body: {
      large: {
        fontSize: '16px',
        lineHeight: '24px',
      },
      medium: {
        fontSize: '14px',
        lineHeight: '20px',
      },
      mediumBold: {
        fontSize: '14px',
        fontWeight: 'bold',
        lineHeight: '20px',
      },
      small: {
        fontSize: '12px',
        lineHeight: '20px',
      },
      smallBold: {
        fontSize: '12px',
        fontWeight: 'bold',
        lineHeight: '20px',
      },
    },
    deprecated: {
      heading: {
        h3: {
          fontSize: '20px',
          fontWeight: 'semibold',
          lineHeight: '30px',
        },
      },
      textBold: {
        fontSize: '14px',
        fontWeight: 'semibold',
        lineHeight: '20px',
      },
      textNormal: {
        fontSize: '14px',
        lineHeight: '20px',
      },
      textSmall: {
        fontSize: '12px',
        lineHeight: '18px',
      },
    },
    title: {
      medium: {
        fontSize: '20px',
        lineHeight: '32px',
      },
      small: {
        fontSize: '16px',
        lineHeight: '24px',
      },
    },
  },
}
