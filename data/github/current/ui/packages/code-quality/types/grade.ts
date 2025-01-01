export const Grade = {
  A: 'A',
  B: 'B',
  C: 'C',
  D: 'D',
} as const

export type Grade = (typeof Grade)[keyof typeof Grade]

export const gradeToText = {
  [Grade.A]: 'Excellent',
  [Grade.B]: 'Good',
  [Grade.C]: 'Fair',
  [Grade.D]: 'Needs Improvement',
}
