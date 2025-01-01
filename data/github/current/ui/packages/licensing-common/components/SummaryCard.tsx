import type {ComponentType, ReactNode} from 'react'
import {Label} from '@primer/react'
import type {IconProps} from '@primer/octicons-react'
import {clsx} from 'clsx'
import styles from './SummaryCard.module.css'
import {ProductActivationState} from '../types/product-activation-state'

interface SummaryCardProps {
  children?: ReactNode
  headerIconComponent: ComponentType<IconProps>
  headerActions?: ReactNode
  headerMenu?: ReactNode
  headerLabels?: ReactNode[]
  productActivationState?: ProductActivationState
  title: string
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
        <div className={clsx(styles.summaryCardHeaderContainer)}>
          <div className="d-flex gap-2">
            <div className="p-2 bgColor-default border rounded-2">
              <props.headerIconComponent className="d-block" size={16} />
            </div>
            <h2 className="d-flex flex-items-center" data-testid="summary-card-title">
              {props.title}
            </h2>
            {props.headerLabels}
            {props.productActivationState && <HeaderLabel productActivationState={props.productActivationState} />}
          </div>
          {props.headerActions ? (
            <div className={clsx(styles.summaryCardHeaderActionsContainer)} data-testid="summary-card-header-actions">
              {props.headerActions}
            </div>
          ) : null}
        </div>
        {props.headerMenu ? (
          <div className="ml-auto flex-self-start" data-testid="summary-card-header-menu">
            {props.headerMenu}
          </div>
        ) : null}
      </div>
      {props.children}
    </div>
  )
}

function HeaderLabel({productActivationState}: {productActivationState: ProductActivationState}) {
  return (
    <>
      {productActivationState === ProductActivationState.Inactive && (
        <Label variant="default" data-testid="summary-card-label-inactive">
          Disabled
        </Label>
      )}
      {productActivationState === ProductActivationState.Trial && (
        <Label variant="accent" data-testid="summary-card-label-trial">
          Trial
        </Label>
      )}
      {productActivationState === ProductActivationState.TrialExpired && (
        <Label variant="attention" data-testid="summary-card-label-trial-expired">
          Trial expired
        </Label>
      )}
    </>
  )
}
