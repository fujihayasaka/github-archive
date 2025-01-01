import StoryBookWarning from './StorybookWarningComponent'

export const getRenderWarnings = () => {
  let warnings: string[] = []
  return {
    warnIf: (pred: boolean, warning: string): void => {
      if (pred) warnings = [...warnings, warning]
    },
    RenderWarnings: () => StoryBookWarning(warnings),
  }
}
