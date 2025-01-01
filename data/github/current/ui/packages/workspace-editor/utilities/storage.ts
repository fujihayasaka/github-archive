const encoder = new TextEncoder()
const MAX_STORAGE_SIZE = 5 * 1024 * 1024 // 5MiB is the default limit for localStorage
const PERCENTAGE_THRESHOLD = 90

export function getTotalStorageUsed(): number {
  let totalStorageUsed = 0
  for (let i = 0; i < localStorage.length; i++) {
    const key = localStorage.key(i) ?? ''
    const value = localStorage.getItem(key) ?? ''
    totalStorageUsed += encoder.encode(key).length + encoder.encode(value).length
  }
  return totalStorageUsed
}

export function percentageStorageUsed(storage: number): number {
  return (storage / MAX_STORAGE_SIZE) * 100
}

export function reachedStorageThreshold(storage: number): boolean {
  return percentageStorageUsed(storage) >= PERCENTAGE_THRESHOLD
}
