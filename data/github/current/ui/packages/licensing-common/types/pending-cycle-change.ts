export interface PendingCycleChange {
  changeType: 'change' | 'downgrade'
  effectiveDate: Date
  id?: number
  isCancellation?: boolean
  isChangingDuration: boolean
  isChangingSeats: boolean
  newPrice: string
  newSeatCount: number
  planDisplayName: string
  planDuration: string
}
