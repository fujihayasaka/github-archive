export const ConsentValue = {
  EXPLICIT: 'optInExplicit',
  IMPLICIT: 'optInImplicit',
} as const

type ConsentValue = (typeof ConsentValue)[keyof typeof ConsentValue]

export interface Country {
  name: string
  alpha: string
}
