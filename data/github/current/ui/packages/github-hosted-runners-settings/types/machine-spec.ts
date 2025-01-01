export const MachineSpecArchitecture = {
  x64: 'X64',
  ARM64: 'Arm64',
} as const

export type MachineSpecArchitecture = (typeof MachineSpecArchitecture)[keyof typeof MachineSpecArchitecture]

export type MachineSpec = {
  id: string
  architecture: MachineSpecArchitecture
  storageGb: number
  memoryGb: number
  cpuCores: number
  type: 'basic' | 'gpu_optimized'
  documentationUrl: string
  gpu: {
    name: string
    count: number
    memoryGb: number
  } | null
}
