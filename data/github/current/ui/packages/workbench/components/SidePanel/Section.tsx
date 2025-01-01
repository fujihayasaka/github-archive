import {ChevronDownIcon, ChevronRightIcon, type Icon} from '@primer/octicons-react'
import {Button} from '@primer/react'
import {SkeletonText, useSlots} from '@primer/react/experimental'
import {clsx} from 'clsx'
import {type ChangeEvent, createElement, type PropsWithChildren, type ReactNode, useState} from 'react'

import {ReadOnlyProvider, useReadOnly} from '../../contexts/ReadOnlyContext'
import {SectionProvider, useSection} from '../../contexts/SectionContext'
import styles from './Section.module.css'

export interface SectionProps {
  title: string
  open?: boolean
  readOnly?: boolean
  loading?: boolean
  variant?: 'default' | 'bordered'
  showTitle?: boolean
}

export type SetIsExpanded = (value: boolean) => void

function Section({
  title,
  children,
  readOnly = false,
  loading = false,
  variant = 'default',
  showTitle = true,
}: PropsWithChildren<SectionProps>) {
  const [slots, ...rest] = useSlots(children, {
    primaryAction: PrimaryAction,
    items: Items,
  })
  return (
    <ReadOnlyProvider readOnly={readOnly}>
      <SectionProvider loading={loading}>
        <div
          className={clsx(styles.detailsContent, {
            [styles.detailsContentBordered]: variant === 'bordered',
          })}
        >
          {showTitle && <span className={styles.summary}>{title}</span>}
          {slots.primaryAction}
          <>{!loading ? slots.items : <LoadingItem />}</>
          {rest}
        </div>
      </SectionProvider>
    </ReadOnlyProvider>
  )
}

const Group = ({label, children, columns = 2}: {label: string; children: ReactNode; columns?: 1 | 2}) => {
  return (
    <div className={styles.groupContainer}>
      <div className={styles.groupLabel}>{label}</div>
      <div
        className={styles.groupContent}
        style={{
          '--columns': columns === 1 ? '1fr' : '1fr 1fr',
        }}
      >
        {children}
      </div>
    </div>
  )
}

const GroupLabels = ({label1, label2}: {label1: string; label2: string}) => {
  return (
    <div className={styles.groupLabelsContainer}>
      <span className={styles.label1}>{label1}</span>
      <span className={styles.label2}>{label2}</span>
    </div>
  )
}

const Items = ({children}: {children: ReactNode}) => children

type ItemProps = {
  title: ReactNode
  description?: ReactNode
  icon: Icon
  onSelect?: () => void
  expandable?: boolean
  renderContent?: (props: {setIsExpanded: SetIsExpanded}) => ReactNode
}
const Item = ({title, description, icon: Icon, onSelect, expandable, renderContent}: ItemProps) => {
  const [isExpanded, setIsExpanded] = useState<boolean>(false)
  return (
    <div className={`border rounded-2 mt-1 p-3 position-relative ${styles.item}`}>
      <Icon className={`fgColor-muted ${styles.itemIcon}`} />
      <p className={`mb-0 text-bold ${styles.itemTitle}`}>{title}</p>
      {expandable ? (
        <Button
          className={clsx(styles.itemExpandButton, !isExpanded && styles.itemBreakoutButton)}
          size="small"
          variant="invisible"
          onClick={() => setIsExpanded(!isExpanded)}
          aria-label={`Edit ${title}`}
        >
          {isExpanded ? <ChevronDownIcon size={16} /> : <ChevronRightIcon size={16} />}
        </Button>
      ) : (
        onSelect && (
          <button
            className={clsx('float-right', styles.itemIconButton, styles.itemBreakoutButton)}
            type="button"
            onClick={!expandable ? onSelect : () => setIsExpanded(!isExpanded)}
            aria-label={`Edit ${title}`}
          >
            <ChevronRightIcon size={1} />
          </button>
        )
      )}
      {!expandable || !isExpanded ? (
        description ? (
          <p className={`mb-0 fgColor-muted ${styles.itemDescription}`}>{description}</p>
        ) : null
      ) : (
        renderContent && <div className={styles.itemExpandedContent}>{renderContent({setIsExpanded})}</div>
      )}
    </div>
  )
}

const LoadingItem = () => {
  return (
    <div>
      {['50%', '75%'].map(width => (
        // eslint-disable-next-line primer-react/no-system-props
        <SkeletonText key={width} size="titleMedium" className={`mb-0 ${styles.itemTitle}`} width={width} />
      ))}
    </div>
  )
}

const RadioGroup = ({children}: {children: ReactNode}) => {
  return <div className={styles.radioGroup}>{children}</div>
}

const RadioGroupItem = ({
  children,
  value,
  name,
  checked,
  onChange,
  icon,
}: {
  children: ReactNode
  value: string
  name: string
  checked?: boolean
  onChange?: (event: ChangeEvent<HTMLInputElement>) => void
  icon?: Icon
}) => {
  const readOnly = useReadOnly()
  return (
    <label className={styles.radioItem}>
      <input
        type="radio"
        disabled={readOnly}
        name={name}
        value={value}
        checked={checked}
        onChange={onChange}
        className={styles.radioInput}
      />
      {icon && <span className={styles.radioIcon}>{createElement(icon)}</span>}
      <span className="text-small">{children}</span>
    </label>
  )
}

const PrimaryAction = ({
  icon,
  onSelect,
  disabled = false,
  children,
}: PropsWithChildren<{
  icon: Icon
  disabled?: boolean
  onSelect: () => void
}>) => {
  const readOnly = useReadOnly()
  const {loading} = useSection()
  if (loading) return null
  return (
    <Button
      size="medium"
      variant="default"
      leadingVisual={icon}
      onClick={onSelect}
      disabled={disabled || readOnly || loading}
      block
      loading={loading}
    >
      {children}
    </Button>
  )
}

Section.Group = Group
Section.GroupLabels = GroupLabels
Section.Item = Item
Section.Items = Items
Section.RadioGroup = RadioGroup
Section.RadioGroupItem = RadioGroupItem
Section.PrimaryAction = PrimaryAction

export {Section}
