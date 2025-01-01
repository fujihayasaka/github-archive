import ForresterResearch from './logos/ForresterResearch'
import Gartner from './logos/Gartner'

/**
 * Render SVG logo as React component.
 *
 * When adding a new logo:
 * - Logos must have a <title> tag for accessibility.
 * - If an SVG has className such as `st0` or `st1`, namespace the class to avoid conflicts. e.g. from .sg0 to .company-sg0
 * - Pro tip: If you're given a figma file, you can right click on the logo and copy the SVG code directly.
 */
export const LogoSuiteMap: {[key: string]: () => JSX.Element} = {
  'Forrester Research': ForresterResearch,
  Gartner,
}

export const Logo = ({name}: {name: string}) => {
  const Component = LogoSuiteMap[name]
  if (Component) {
    return <Component />
  }
  return null
}
