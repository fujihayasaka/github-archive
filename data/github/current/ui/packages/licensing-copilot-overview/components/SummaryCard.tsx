import type {ComponentType, ReactNode} from 'react'
import type {IconProps} from '@primer/octicons-react'
import {clsx} from 'clsx'
import styles from './SummaryCard.module.css'

interface SummaryCardProps {
  headerIconComponent: ComponentType<IconProps>
  title: string
  children?: ReactNode
  headerButtons?: ReactNode
}

export function SummaryCard(props: SummaryCardProps) {
  return (
    <div className="Box d-flex flex-column gap-0">
      <div
        className={clsx(
          'Box-header',
          'd-flex',
          'flex-row',
          'flex-items-center',
          'gap-2',
          !props.children && styles.summaryCardHeaderNoBody,
        )}
        data-testid="summary-card-header"
      >
        <div className="p-2 bgColor-default border rounded-2">
          <props.headerIconComponent className="d-block" size={16} />
        </div>
        <div className="flex-1 d-flex flex-row flex-items-center gap-2">
          <h3 className="text-normal f3" data-testid="summary-card-title">
            {props.title}
          </h3>
        </div>
        {props.headerButtons ? <div data-testid="summary-card-header-buttons">{props.headerButtons}</div> : null}
      </div>
      {props.children ? (
        <div className="Box-footer pt-0 px-0" data-testid="summary-card-body">
          {props.children}
        </div>
      ) : null}
    </div>
  )
}
