// These values were hardcoded to mimic the colors in GitHub Actions.
// Note: The colors do NOT match the Primer doc's CSS variables, which don't match the actual CSS variable values.
//       Hardcoding these values is the simplest way to get the same colors.
export const colors = {
  actionListItem: {
    default: {
      hoverBg: 'rgba(177, 186, 196, 0.12)',
    },
  },
  canvas: {
    inset: '#010409',
  },
  control: {
    bg: {
      active: '#31363e',
    },
  },
  fg: {
    attention: '#d29922',
    danger: '#f85149',
    default: '#f0f6fc',
    muted: '#9198a1',
    success: '#3fb950',
  },
  misc: {
    pending: '#dbab0a',
  },
}
