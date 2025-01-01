import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'

import styles from './RightSidePanel.module.css'

export function RightSidePanelContent({
  children,
  padding = 3,
  error = false,
}: {
  children: React.ReactNode
  padding?: 2 | 3
  error?: boolean
}) {
  const showErrorOnFailedApplicationSuggestion = useFeatureFlag('add_banner_for_failed_application_of_suggestion')

  const paddingClassName = padding === 3 ? 'p-3' : 'p-2'
  const opacityClassname = showErrorOnFailedApplicationSuggestion && error ? 'opacity50' : 'opacity100'
  return (
    <div className={`d-flex flex-column flex-1 overflow-y-auto pb-0 ${paddingClassName} ${styles[opacityClassname]}`}>
      {children}
    </div>
  )
}

export function RightSidePanelFooter({children}: {children: React.ReactNode}) {
  return <div className="d-flex flex-row p-2 flex-justify-between border-top">{children}</div>
}

interface RightSidePanelHeaderProps {
  leftContent?: React.ReactNode
  title: string | React.ReactNode
  rightContent?: React.ReactNode
}

export function RightSidePanelHeader({title, leftContent, rightContent}: RightSidePanelHeaderProps) {
  return (
    <>
      {!!leftContent && <div className="flex-shrink-0">{leftContent}</div>}
      <h2 className={`${styles.panelHeading} pl-2`}>{title}</h2>
      {!!rightContent && <div className="flex-shrink-0 pl-2">{rightContent}</div>}
    </>
  )
}
