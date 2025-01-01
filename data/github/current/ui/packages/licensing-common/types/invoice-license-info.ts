interface RenewalStatusMessageProps {
  text: string
  variant: 'success' | 'critical'
}

export interface InvoiceLicenseInfo {
  actionType?: 'renewal' | 'upgrade'
  expired: boolean
  hasFutureRenewal: boolean
  renewalScheduledStartDate?: string
  isGHASRenewal?: boolean
  isGHERenewal?: boolean
  statusMessage?: RenewalStatusMessageProps
}
