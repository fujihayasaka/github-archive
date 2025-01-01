export interface ServerLicense {
  reference_number: string
  seats: number
  expires_at: string
  code_security_enabled: boolean
  secret_protection_enabled: boolean
}
