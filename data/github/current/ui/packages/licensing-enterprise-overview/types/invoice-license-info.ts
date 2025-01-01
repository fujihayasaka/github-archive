interface RenewalStatusMessageProps {
  text: string
  variant: 'success' | 'critical'
}

export interface InvoiceLicenseInfo {
  actionType?: 'renewal' | 'upgrade'
  renewalScheduledStartDate?: Date
  isGHERenewal?: boolean
  statusMessage?: RenewalStatusMessageProps
}
