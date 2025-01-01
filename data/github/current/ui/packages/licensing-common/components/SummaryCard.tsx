import type {ComponentType, ReactNode} from 'react'
import {Label} from '@primer/react'
import type {IconProps} from '@primer/octicons-react'
import {clsx} from 'clsx'
import styles from './SummaryCard.module.css'
import {ProductActivationState} from '../types/product-activation-state'

interface SummaryCardProps {
  children?: ReactNode
  headerIconComponent: ComponentType<IconProps>
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
        <div className="p-2 bgColor-default border rounded-2">
          <props.headerIconComponent className="d-block" size={16} />
        </div>
        <div className="flex-1 d-flex flex-row flex-items-center gap-2">
          <h2 data-testid="summary-card-title">{props.title}</h2>
          {props.headerLabels}
          {props.productActivationState && <HeaderLabel productActivationState={props.productActivationState} />}
        </div>
        {props.headerMenu ? <div data-testid="summary-card-header-menu">{props.headerMenu}</div> : null}
      </div>
      {props.children ? (
        <div className="Box-footer pt-0 px-0" data-testid="summary-card-body">
          {props.children}
        </div>
      ) : null}
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
          Active trial
        </Label>
      )}
      {productActivationState === ProductActivationState.TrialExpired && (
        <Label variant="attention" data-testid="summary-card-label-trial-expired">
          Expired trial
        </Label>
      )}
    </>
  )
}
